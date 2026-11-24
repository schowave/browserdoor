# /// script
# requires-python = ">=3.11"
# dependencies = ["marionette-driver==3.7.1", "lz4==4.4.5"]
# ///
"""Zen contract test: checks what Browserdoor relies on in Zen, against a real Zen.

1. A fresh profile gets two spaces, Alpha and Beta, created through Zen's own UI code.
2. After Zen quits, `<profile>/zen-sessions.jsonlz4` must hold them in `spaces[]` with
   `uuid`, `name`, `icon` and `theme.gradientColors` (SPEC 3.1). The spaces are written to
   `--spaces-out` so the Swift and Rust parsers can be checked against the same file.
3. Cold start: `zen --profile P --space <Beta> URL` opens URL in Beta, with Beta active.
4. Running: Zen sits in Alpha; a second `zen --profile P --space <Beta> URL` hands the URL to
   the running instance, which opens it in Beta and switches to Beta.

The profile is a temporary directory, so the user's own Zen is never touched, even while it
runs. Usage: uv run contract/zen_contract.py --zen <path to the zen executable>
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import lz4.block
from marionette_driver.marionette import Marionette

PREFS = {
    "marionette.port": 0,  # pick a free port, written to MarionetteActivePort
    "browser.shell.checkDefaultBrowser": False,
    "browser.aboutwelcome.enabled": False,
    "zen.welcome-screen.seen": True,
    "browser.startup.homepage_override.mstone": "ignore",
    "datareporting.policy.dataSubmissionEnabled": False,
    "app.update.disabledForTesting": True,
    "browser.tabs.warnOnClose": False,
    "browser.warnOnQuit": False,
    "browser.sessionstore.resume_from_crash": False,
}

COLD_URL = "https://example.com/?browserdoor=cold"
WARM_URL = "https://example.org/?browserdoor=warm"
NAME_URL = "https://example.net/?browserdoor=name"


def log(msg: str) -> None:
    print(f"[zen-contract] {msg}".encode("ascii", "backslashreplace").decode(), flush=True)


def fail(msg: str) -> None:
    print(f"::error::Zen contract: {msg}".encode("ascii", "backslashreplace").decode(), flush=True)
    sys.exit(1)


def read_mozlz4(path: Path) -> dict:
    data = path.read_bytes()
    if data[:8] != b"mozLz40\0":
        fail(f"{path.name} does not start with the mozLz4 magic")
    size = struct.unpack("<I", data[8:12])[0]
    return json.loads(lz4.block.decompress(data[12:], uncompressed_size=size))


class Zen:
    def __init__(self, binary: Path, profile: Path):
        self.binary = binary
        self.profile = profile
        self.proc: subprocess.Popen | None = None
        self.client: Marionette | None = None

    def args(self, *extra: str) -> list[str]:
        return [str(self.binary), "--profile", str(self.profile), *extra]

    def start(self, *extra: str) -> None:
        port_file = self.profile / "MarionetteActivePort"
        port_file.unlink(missing_ok=True)
        # Windows: the launcher process would exit at once (-wait-for-browser keeps it until the
        # browser ends) and, when elevated, restart Zen through the shell without our environment.
        win = ["-wait-for-browser", "-no-deelevate"] if sys.platform == "win32" else []
        cmd = self.args("--marionette", *win, *extra)
        log("start: " + " ".join(cmd))
        env = {**os.environ, "MOZ_REMOTE_ALLOW_SYSTEM_ACCESS": "1"}
        self.proc = subprocess.Popen(cmd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 90
        while not port_file.exists():
            if self.proc.poll() is not None:
                fail(f"Zen exited with {self.proc.returncode} before Marionette came up")
            if time.time() > deadline:
                fail("Marionette did not come up within 90 s")
            time.sleep(0.5)
        time.sleep(0.5)
        port = int(port_file.read_text().strip())
        self.client = Marionette(host="127.0.0.1", port=port)
        self.client.start_session()
        self.client.set_context(self.client.CONTEXT_CHROME)
        self.script("await gZenWorkspaces.promiseInitialized; return true;")

    def script(self, body: str, args: list | None = None, timeout: float = 30):
        """Runs `body` as an async function in the browser window's chrome scope."""
        assert self.client
        self.client.timeout.script = timeout
        wrapped = (
            "const [args, done] = [arguments[0], arguments[arguments.length - 1]];"
            "(async () => {" + body + "})().then(v => done({ok: v}), e => done({err: String(e) + '\\n' + e.stack}));"
        )
        result = self.client.execute_async_script(wrapped, script_args=[args or []])
        if "err" in result:
            fail(f"script failed: {result['err']}")
        return result["ok"]

    def state(self) -> dict:
        """Every tab of every browser window, with its space and its window's active space. Zen's
        gBrowser.tabs leaves out the tabs of other spaces, so this asks the space manager."""
        return self.script(
            """
            const windows = [...Services.wm.getEnumerator('navigator:browser')];
            const tabs = [];
            windows.forEach((w, i) => {
              const all = w.gZenWorkspaces?.allStoredTabs ?? w.gBrowser.tabs;
              for (const t of all) {
                tabs.push({url: t.linkedBrowser?.currentURI?.spec ?? '', space: t.getAttribute('zen-workspace-id'),
                           window: i, active: w.gZenWorkspaces?.activeWorkspace});
              }
            });
            return {windows: windows.length, active: gZenWorkspaces.activeWorkspace, tabs,
                    spaces: gZenWorkspaces.getWorkspaces().map(s => ({uuid: s.uuid, name: s.name}))};
            """
        )

    def wait_for_tab(self, url: str, timeout: float = 30) -> dict:
        deadline = time.time() + timeout
        while True:
            st = self.state()
            if any(t["url"] == url for t in st["tabs"]):
                return st
            if time.time() > deadline:
                fail(f"no tab with {url} after {timeout:.0f} s; state: {json.dumps(st)}")
            time.sleep(0.5)

    def quit(self) -> None:
        if self.client:
            try:
                # Marionette:Quit directly: the driver's quit() only works for a Zen it launched.
                self.client._send_message("Marionette:Quit", {"flags": ["eAttemptQuit"]})
            except Exception as e:  # noqa: BLE001 - a quit that races the socket is fine
                log(f"quit: {e}")
            self.client = None
        if self.proc:
            try:
                self.proc.wait(timeout=60)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.proc = None


def expect_in_space(st: dict, url: str, space: dict, case: str) -> None:
    tab = next(t for t in st["tabs"] if t["url"] == url)
    names = {s["uuid"]: s["name"] for s in st["spaces"]}
    if tab["space"] != space["uuid"]:
        fail(f"{case}: {url} opened in {names.get(tab['space'], tab['space'])}, not {space['name']}")
    if tab["active"] != space["uuid"]:
        fail(f"{case}: its window shows {names.get(tab['active'], tab['active'])}, not {space['name']}")
    if st["windows"] != 1:
        fail(f"{case}: Zen has {st['windows']} windows; the link should open in the existing one")
    log(f"ok: {case}")


def wait_active(zen: Zen, space: dict, timeout: float = 15) -> dict:
    deadline = time.time() + timeout
    while True:
        st = zen.state()
        if st["active"] == space["uuid"] or time.time() > deadline:
            return st
        time.sleep(0.3)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--zen", required=True, type=Path, help="the zen executable")
    ap.add_argument("--spaces-out", type=Path, help="write the spaces read from the session file here")
    ap.add_argument("--profile-out", type=Path, help="copy the profile's zen-sessions.jsonlz4 here")
    ap.add_argument("--keep", action="store_true", help="keep the temporary profile")
    a = ap.parse_args()

    tmp = Path(tempfile.mkdtemp(prefix="zen-contract-"))
    profile = tmp / "profile"
    profile.mkdir()
    (profile / "user.js").write_text(
        "".join(f'user_pref("{k}", {json.dumps(v)});\n' for k, v in PREFS.items()), encoding="utf-8"
    )
    zen = Zen(a.zen.resolve(), profile)
    try:
        # 1. Two spaces through Zen's own code, then quit so the session file is written.
        zen.start()
        made = zen.script(
            """
            const made = [];
            for (const [name, icon] of [['Alpha', '🅰️'], ['Beta', '']]) {
              const ws = await gZenWorkspaces.createAndSaveWorkspace(name, icon || undefined, true);
              ws.name = name;
              await gZenWorkspaces.saveWorkspace(ws);
              made.push({uuid: ws.uuid, name});
            }
            return made;
            """
        )
        alpha, beta = made
        log(f"spaces: {json.dumps(zen.state()['spaces'])}")
        zen.quit()

        # 2. The session file, as Browserdoor reads it.
        session = read_mozlz4(profile / "zen-sessions.jsonlz4")
        spaces = session.get("spaces")
        if not isinstance(spaces, list):
            fail(f"zen-sessions.jsonlz4 has no spaces[]; top-level keys: {sorted(session)}")
        by_uuid = {s.get("uuid"): s for s in spaces}
        for want in made:
            s = by_uuid.get(want["uuid"])
            if not s:
                fail(f"space {want['name']} is missing from zen-sessions.jsonlz4")
            if s.get("name") != want["name"]:
                fail(f"space {want['uuid']} is named {s.get('name')!r}, not {want['name']!r}")
            if "icon" not in s and want["name"] == "Alpha":
                fail("space Alpha has no icon field")
            colors = (s.get("theme") or {}).get("gradientColors")
            if not isinstance(colors, list):
                fail(f"space {want['name']} has no theme.gradientColors list: {json.dumps(s.get('theme'))}")
        log("ok: session file has spaces[] with uuid, name, icon, theme.gradientColors")
        if a.spaces_out:
            a.spaces_out.write_text(json.dumps(
                [{"uuid": s["uuid"], "name": s["name"], "icon": s.get("icon") or ""} for s in spaces],
                ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if a.profile_out:
            shutil.copy(profile / "zen-sessions.jsonlz4", a.profile_out)

        # 3. Cold start into Beta.
        zen.start("--space", beta["uuid"], COLD_URL)
        st = zen.wait_for_tab(COLD_URL)
        st = wait_active(zen, beta)
        expect_in_space(st, COLD_URL, beta, "cold start with --space <uuid>")

        # 4. Running: back to Alpha, then a second process hands over --space Beta.
        zen.script("await gZenWorkspaces.changeWorkspaceWithID(args[0]); return true;", [alpha["uuid"]])
        if zen.state()["active"] != alpha["uuid"]:
            fail("could not switch the running Zen to Alpha")
        handoff = subprocess.run(zen.args("--space", beta["uuid"], WARM_URL), timeout=60, capture_output=True, text=True)
        log(f"hand-off process exited with {handoff.returncode}: {(handoff.stdout + handoff.stderr).strip()[:500]}")
        zen.wait_for_tab(WARM_URL)
        st = wait_active(zen, beta)
        expect_in_space(st, WARM_URL, beta, "running Zen with --space <uuid>")

        # 5. Running, by name (case-insensitive), back to Alpha.
        subprocess.run(zen.args("--space", "alpha", NAME_URL), timeout=60,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        zen.wait_for_tab(NAME_URL)
        st = wait_active(zen, alpha)
        expect_in_space(st, NAME_URL, alpha, "running Zen with --space <name>")
        zen.quit()
        log("all checks passed")
    finally:
        zen.quit()
        if a.keep:
            log(f"profile kept at {profile}")
        else:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    os.environ.setdefault("PYTHONUNBUFFERED", "1")
    main()
