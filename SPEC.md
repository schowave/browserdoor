# Browserdoor — Specification

Browserdoor is a link picker for macOS and Windows in the style of Browserosaurus. It is registered as the default browser. When you click a link, a panel appears at the mouse position. In it you choose the target: a **Zen space**, a **Chromium profile**, a **Firefox profile** or another installed browser.

## 1. Scope

**Included**
- Default browser for `http`, `https`, `.html` and `.webloc`
- Picker with a mixed target list: Zen spaces, Chromium browsers × profiles, Firefox profiles, other browsers
- Settings window, backed by a JSON configuration file
- Installation via a Homebrew formula from a dedicated tap, or as a notarized DMG that updates itself (see 10.2)
- Windows: the same app for Windows 11, installed with Scoop (see 2.1). The sections marked *Windows* say where it differs; everything else applies to both.

**Not included**
- Rule engine (à la Finicky)
- Bypassing the picker via a modifier key
- Editable URL in the picker
- `mailto:`
- More than one Zen profile at a time
- Firefox containers as separate targets
- Safari profiles (Safari has no command line for them)
- Linux (a later step, see ADR 0001); Windows 10 and installers other than Scoop

## 2. Platform

- Swift 6, SwiftUI and AppKit, **macOS 14+**. Built with Swift Package Manager and Xcode 16 or later.
- The app runs in the background: `LSUIElement` (no Dock icon), a menu bar icon (see 6.1), autostart via a LaunchAgent (see 8.3).
- English and German according to the system language (`Resources/Localization/*.lproj/Localizable.strings`, key = English text). `mise run check-strings` checks that every key is translated.
- Its only network access is the update check (see 7).
- License: MIT. The repo is public on GitHub.

### 2.1 Windows

- Rust and Tauri 2 (WebView2), **Windows 11**, x64 and arm64 ([ADR 0001](docs/adr/0001-windows-port-in-rust-tauri.md)). `windows/core` is the domain without any Windows API; `windows/app` is the Windows shell; `windows/ui` holds the two pages (Svelte 5).
- One **resident instance** per user runs in the background with a tray icon (see 6.4); autostart is a `Run` value in the registry (see 8.6).
- English and German according to the Windows display language (`windows/app/src/i18n.rs`, `windows/ui/src/lib/i18n.ts`, key = English text).
- Its only network access is the update check (see 7.3).

## 3. Targets

A **target** is an entry in the picker. Every target has a stable `id`, a display name, an icon and a way to open links.

| Kind | ID scheme | Opening |
|---|---|---|
| Zen space | `zen:{<uuid>}` | Zen is running: `<Zen.app>/Contents/MacOS/zen --space "{uuid}" <url>` per URL. Zen is not running: `open -a <Zen.app> --args --space "{uuid}" <url…>` |
| Zen without workspace support | `app:app.zen-browser.zen` | like a regular browser |
| Chromium profile | `chromium:<bundleId>:<profileDir>` | `open -na <App> --args --profile-directory=<dir> <url…>` |
| Firefox profile | `firefox:<bundleId>:<profilePath>` | `open -na <App> --args --profile <dir> <url…>` |
| Regular browser | `app:<bundleId>` | `NSWorkspace.open(urls, withApplicationAt:)` |

### 3.1 Zen

- **App**: the bundle ID `app.zen-browser.zen` among the https handlers (path filter, see 3.4).
- **Profile**: from `~/Library/Application Support/zen/profiles.ini`: the `Default=` line of the `[Install…]` section, else the profile with `Default=1`. `zen.profilePath` in the configuration overrides it; then every Zen call also gets `--profile <path>`, so `--space` reaches the instance with this profile.
- **Workspaces**: in `<profile>/zen-sessions.jsonlz4`, read again **every time the picker opens**.
  - Format mozLz4: the magic `mozLz40\0` (8 bytes), the size as uint32 LE, then a raw LZ4 block.
  - Browserdoor reads `spaces[]`, each with `uuid`, `name`, `icon` and `theme.gradientColors`.
- **Icons**: `icon` is a `chrome://browser/skin/zen-icons/selectable/<name>.svg` URL, an emoji or empty.
  - The SVGs are in `<Zen.app>/Contents/Resources/browser/omni.ja` (a zip) under `chrome/browser/skin/classic/browser/zen-icons/selectable/`. They are extracted once per Zen version to `~/Library/Caches/io.github.schowave.browserdoor/zen-icons/<version>/`.
  - An emoji is shown directly; without an icon, the initial letter appears on the theme color.
- **Version check**: `--space` exists from Zen 1.24 on (zen-browser/desktop#15074). If Zen is older (`CFBundleShortVersionString`) or the file can't be read, Zen appears as a single `app:` target.
- **Opening**: If Zen is not running, Browserdoor starts it through LaunchServices (`open -a … --args --space …`), so Zen is not its child process; Zen keeps the space for its own launch (`zen.workspaces.cmdline-initial-workspace`). If Zen is running, the direct call hands over to the running instance and returns at once (tested with 1.24.1b); then Browserdoor activates Zen.

### 3.2 Chromium browsers

- **Supported** (`bundleId` → data directory under `~/Library/Application Support/`):
  - `com.google.Chrome` → `Google/Chrome`
  - `com.google.Chrome.beta` → `Google/Chrome Beta`
  - `com.google.Chrome.canary` → `Google/Chrome Canary`
  - `com.brave.Browser` → `BraveSoftware/Brave-Browser`
  - `com.microsoft.edgemac` → `Microsoft Edge`
  - `com.vivaldi.Vivaldi` → `Vivaldi`
  - `org.chromium.Chromium` → `Chromium`
- **Profiles**: `<datadir>/Local State`, `profile.info_cache`: `<profileDir>` → `{name}`.
- With **exactly one** profile the browser appears as one entry without a profile name; its ID stays `chromium:<bundleId>:<profileDir>`.

### 3.3 Firefox

- **Supported**: `org.mozilla.firefox` with `~/Library/Application Support/Firefox`. Developer Edition and Nightly share that directory and stay single `app:` entries; otherwise every profile would be listed three times.
- **Profiles**: the `[ProfileN]` sections of `profiles.ini` (`Name`, `Path`, `IsRelative`). `profilePath` in the target ID is `Path` as Firefox stores it.
  - Since Firefox 138 the profile manager keeps a profile group in `Profile Groups/<StoreID>.sqlite` (table `Profiles`: `id`, `path`, `name`, …; `path` relative to the data directory). `profiles.ini` lists only one profile of the group, marked `StoreID=`; it is replaced by the group's profiles.
  - The database runs in WAL mode. Browserdoor copies it with its `-wal` file to a temporary directory and reads the copy, so new profiles show at once and Firefox's files stay untouched.
  - Order: first the profiles an `[Install…]` section names as `Default=`, then the others by section number or `id`.
  - The empty `default` profile Firefox creates next to `default-release` is dropped, unless an installation uses it.
- With **at most one** profile, Firefox stays a single `app:` target.
- **Opening**: always `open -na`, so Firefox is not Browserdoor's child process. If the profile is running, the new instance hands the URLs over and quits (tested with Firefox 160); otherwise Firefox starts with this profile.

### 3.4 Other browsers

- The basis is every app that can open `https` (`NSWorkspace.urlsForApplications(toOpen:)`).
- **Path filter**: only apps under `/Applications`, `~/Applications` or `/System`. Copies in caches or snapshots (Playwright, Puppeteer, …) are dropped. If a bundle ID occurs more than once, the first allowed copy wins.
- **Allowlist**: only known browsers (`KnownBrowsers`, as in Browserosaurus), plus the bundle IDs in `extraApps`. Otherwise LaunchServices would also list terminals, web-app wrappers, Finicky, Browserosaurus etc.
- Excluded: Browserdoor itself, and Zen, the Chromium browsers and Firefox where 3.1 to 3.3 already list them.

### 3.5 Allowed URLs

URLs reach the browsers as command-line arguments, so Browserdoor lets only `http`, `https` and `file` through (`URLPolicy`); everything else, such as `--remote-debugging-port=…` or `javascript:`, is discarded. From `.webloc` files only `http` and `https` are accepted, so a downloaded file can't open a local one. The check runs on receipt and again when the launch commands are built.

### 3.6 Windows

- **App ID** instead of bundle ID: the browser's key under `Software\Clients\StartMenuInternet`, or the path of the `.exe` for an added app. Target IDs keep their schemes (`zen:{uuid}`, `chromium:<appId>:<dir>`, `firefox:<appId>:<path>`, `app:<appId>`), so a configuration only works on the computer it was made on.
- **Discovery** reads the browsers registered under `StartMenuInternet` in HKCU, then HKLM (64- and 32-bit view); the first entry per App ID and per `.exe` wins, Browserdoor's own entry and Internet Explorer (which only opens Edge on Windows 11) are skipped. That list holds browsers only, so there is no allowlist. Name: the key's default value, else `Capabilities\ApplicationName`; program: `shell\open\command`.
- **Families** are recognized by the end of the `.exe` path:
  - Chromium (data under `%LOCALAPPDATA%`): `\Google\Chrome\Application\chrome.exe` → `Google\Chrome\User Data`, likewise `Chrome Beta`, `Chrome Dev`, `Chrome SxS` (Canary), `BraveSoftware\Brave-Browser\Application\brave.exe`, `Microsoft\Edge…\Application\msedge.exe` (Edge, Beta, Dev), `Vivaldi\Application\vivaldi.exe`, `Chromium\Application\chrome.exe`. Profiles as in 3.2.
  - Firefox: `\Mozilla Firefox\firefox.exe` with `%APPDATA%\Mozilla\Firefox`; profiles and profile groups as in 3.3.
  - Zen: `zen.exe` with `%APPDATA%\zen`; its version is `[App] Version` of the `application.ini` next to `zen.exe`; spaces as in 3.1. The Zen contract test (see 12) checks `--space` and the session file on Windows too.
- **Added apps** (`extraApps`) are `.exe` paths; the name is the file's `FileDescription`. An `.exe` that no longer exists is listed in the settings for removal.
- **Opening** starts the browser directly (`CreateProcess`, detached, after `AllowSetForegroundWindow` so it may come forward): plain browsers `<exe> <url…>`, Chromium `--profile-directory=<dir>`, Firefox `-profile <dir>`, Zen `--space <uuid>` (one call per URL while Zen runs, all URLs in one call on a cold start; `--profile` as in 3.1). Zen is brought forward afterwards. "Zen runs" means a process with that image path exists; one whose path can't be read but whose name matches counts too.
- **Incoming items** are the command-line arguments Windows passes: URLs, or paths of `.html`, `.htm` and `.xhtml` files, which become `file:` URLs. 3.5 applies unchanged.

## 4. Picker

A floating, borderless `NSPanel` at the mouse position, kept within the visible screen area (`PickerPlacement`).

**Content**
- At the top the link (`LinkDisplay`): the host in bold, path, query and fragment in gray.
  - The host is shown as Foundation parses it: non-ASCII hosts appear in Punycode (`xn--…`), so look-alike domains stand out. User info (`https://bank.com@evil.io`) is not shown. A host whose decoded form has characters a host name can't have (`%2F`, `%40`) stays percent-encoded.
  - A long line cuts the path at its end and the host, which gets the room first, in its middle, so the end of the domain stays visible.
  - A `file` link shows its file name in bold and its folder in gray (`~` for the home folder).
  - Several links show as "N links", with every link in the tooltip.
- Below it the targets: icon, name, key. The default target carries a `↩` mark, even while another row is selected. The selected row looks like a selected menu item (system selection color, white text).
- Targets of the same app (Chromium and Firefox profiles) get a small lettered circle on the icon (`ProfileBadge`): the name's first letter, in a color from a fixed palette picked by a stable hash of the target ID. Zen spaces and apps listed once get none.
- A "Copy URL" button.
- If every target is hidden: "No visible targets" and a "Settings…" button.

**Controls**
- A target's key opens it. Without configuration the keys are `1`–`9`, then `0`, in list order; the configuration can set one per target.
- ↑/↓ and Tab/⇧Tab move the selection, Home/End jump to the first/last row, Return opens the selection. The default target is preselected, else the first row.
- Hovering selects a row only once the mouse has moved 2 pt from where it was when the picker opened, so a pointer that happens to rest on a row doesn't replace the default.
- Esc or a click outside closes the picker. ⌘C copies the URL(s). ⌘, closes the picker and opens the settings on the Targets pane.
- For VoiceOver every row is a button with its name as label, its key and the `↩` mark as hint, and its selected state.
- Links that arrive while the picker is open are collected; one choice opens all of them.

### 4.1 Windows

- A borderless, always-on-top window with an acrylic background, created hidden at startup so it appears without starting WebView2. It opens left of and above the mouse (24 × 12 px, scaled for the monitor) and stays 8 px inside the work area of the mouse's monitor (`placement`). The page reports its height, and the window is resized at the same spot.
- Ctrl takes the place of ⌘ (Ctrl+C, Ctrl+,). Ctrl+Alt counts as AltGr, so a character typed with it can be a target's key.
- Hover selects only after the mouse has moved 2 px from where it was first seen over the picker.
- Focus: the launch that brought the link lets the resident instance take the foreground (see 8.6). If Windows still refuses, the picker flashes in the taskbar instead of waiting without focus.
- The list is a listbox for screen readers (Narrator): each row an option with its name and key.

## 5. Configuration

`~/.config/browserdoor/config.json`, optional; without it the defaults apply. Unknown fields are ignored.

```json
{
  "defaultTarget": "zen:{b4ac0402-9e47-4873-89b6-5dfeffe77a7e}",
  "order": ["zen:{3d0f4d74-...}", "zen:{b4ac0402-...}", "app:com.apple.Safari"],
  "hidden": ["app:com.google.Chrome.beta"],
  "extraApps": ["com.googlecode.iterm2"],
  "targets": {
    "zen:{b4ac0402-9e47-4873-89b6-5dfeffe77a7e}": { "label": "David", "hotkey": "d" }
  },
  "zen": { "profilePath": null }
}
```

- **`order`**: these targets come first, in this order. The rest follow in discovery order: Zen spaces in Zen's order, Chromium browsers, Firefox profiles, other browsers alphabetically.
- **`extraApps`**: bundle IDs of apps that aren't known browsers but should be targets.
- **`targets.<id>.label`**: overrides the display name; in the file it is also the readable name next to the UUID.
- Normally the settings window maintains the file (see 6.3). It rewrites it on every change (sorted keys, stable diffs) and keeps the settings of targets that aren't discovered right now.

### 5.1 Windows

`%APPDATA%\Browserdoor\config.json`, same keys and rules; `extraApps` holds `.exe` paths. What the app remembers besides that (onboarding done, tray icon shown, update check) is in `state.json` next to it; problems are logged to `browserdoor.log` there.

## 6. Menu bar and settings

### 6.1 Menu bar icon

`StatusMenu`: a door ajar as a template image (`NSStatusItem`). While Browserdoor isn't the default browser, the icon carries a dot (part of the template image, so macOS tints it like the door); the state is checked when the menu opens, when the app becomes active, after "Make Default Browser" and every 60 s. The icon can be hidden with "Show in menu bar" in the settings or by ⌘-dragging it out of the menu bar; both are the same setting, which macOS keeps in the user defaults with the icon's position. Opening Browserdoor again then shows the settings.

### 6.2 Menu

Rebuilt every time it opens, from cheap queries only, so the status lines are current:
- "About Browserdoor": the standard About panel with links to the repository and the license. With ⌥: "Report an Issue…", which opens GitHub's bug form with the Browserdoor and macOS versions filled in (`IssueReport`) and nothing else.
- "Open Link from Clipboard…": the picker for the links on the clipboard (URL objects, and the links the system's link detector finds in text, without surrounding punctuation; `example.com/x` becomes `http://example.com/x`), filtered like any incoming link. Enabled only while the clipboard holds a web link; from macOS 15.4 the system answers that without Browserdoor reading the clipboard (no privacy notice), before that any text enables it.
- "Make Default Browser" with a warning sign, only when needed.
- "Update to Browserdoor X…" if an update is known, else "Check for Updates…".
- "Settings…" (⌘,). With ⌥: "Show Configuration in Finder".
- "Quit Browserdoor".

### 6.3 Settings window

An `NSWindow` with a toolbar tab per pane, SwiftUI inside. It also opens when Browserdoor is started while it is running (e.g. via `browserdoor`). The window takes the selected pane's title and size and remembers its position; General and Advanced have a fixed size, Targets can be resized and keeps its size.
- *General:* default browser status and button; "Start at login" (the LaunchAgent; the checkmark shows only whether it exists, not whether it is blocked in System Settings; an error shows below the switch); "Show in menu bar"; updates.
- *Targets:* every discovered target with icon and profile badge, sorted by dragging, shown or hidden, renamed, a star for the default target.
  - The key field is a recorder: click it and press a key; Esc cancels, ⌫ removes the custom key. Without a custom key it shows the automatic key in gray. If another target showed that key in the picker, it loses it, and a note under the list says so for a few seconds.
  - **+** adds apps through a selection dialog (`extraApps`; they appear even without an https registration), **−** removes such an app. Added apps no target stands for (uninstalled, or a browser listed by its profiles) appear below the list with a Remove button.
  - A right-click on a target offers Rename (focuses its name), Make Default Target / Remove as Default Target, Hide in Picker / Show in Picker and, for added apps, Remove App.
  - For VoiceOver the checkbox, name, key and star carry labels; the drag handle and icon are hidden.
- *Advanced:* Zen profile; show the configuration file in Finder.
- The picker's ⌘, and its empty-state button open the Targets pane.
- An invisible main menu provides About, ⌘C/⌘V/⌘A, ⌘W, ⌘M, ⌘H and ⌘, for the window.

### 6.4 Windows

- **Tray icon**: the door, white or dark to match the taskbar (`SystemUsesLightTheme`), with the dot while Browserdoor isn't the default browser (the https `UserChoice`/`UserChoiceLatest` ProgID is not `BrowserdoorURL`); the tooltip says so too. Icon and menu are rebuilt when the pointer reaches the icon, every 60 s and after actions. Left and right click open the menu.
- **Menu**: About Browserdoor (version, repository, license); Open Link from Clipboard… (links in the clipboard text as in 6.2, filtered like any incoming link); Make Default Browser…, only when needed; Check for Updates… or Update to Browserdoor X…; Settings…; Quit Browserdoor.
- **Settings window**: Mica background, the panes as tabs.
  - *General*: the default browser button opens the Windows settings for Browserdoor (`ms-settings:defaultapps?registeredAppUser=Browserdoor`); Windows lets only the user choose. "Start at login" (the `Run` value), "Show in notification area" (without the icon, starting Browserdoor again opens the settings), updates.
  - *Targets*: as in 6.3. **+** picks an `.exe`. The key recorder removes a key with Delete or Backspace. Alt+↑/↓ moves a row, F2 or a double-click renames.
  - *Advanced*: Zen profile (a folder picker), "Show in Explorer" for the configuration file.
  - The window reloads its state whenever it comes to the front.

## 7. Updates

Both builds check once a day while "Check for updates automatically" is on (one defaults key, on by default, `UserDefaultsUpdatePreferences`) and when the user asks. Dev builds (version `0.0.0`) are never offered updates. The menu and the settings use one interface, `UpdateChecking`, which each build's `UpdateChecker` conforms to.

### 7.1 Homebrew build

- `HEAD https://github.com/schowave/browserdoor/releases/latest`: the redirect to `…/releases/tag/<tag>` names the newest release (drafts and pre-releases excluded). `api.github.com` is not used, because without a token it allows only 60 requests per hour and IP.
- A newer version (`AppVersion` comparison) shows a dialog. "Later" suppresses the automatic notice for this version. Without a Homebrew installation, the release page is offered instead.
- "Update in Terminal" opens a `.command` script: `brew update && brew upgrade browserdoor`. If `opt/browserdoor` still points where it did, Homebrew had nothing newer: the script says so and Browserdoor keeps running. Otherwise it waits up to 15 s for Browserdoor to restart itself (see 8.4); if it is still running then, the script quits it by its PID and starts it via `browserdoor`.

### 7.2 Download build

`SparkleUpdateChecker.swift`, compiled instead of `UpdateChecker.swift` when `SPARKLE` is defined (see 10.2).
- Sparkle reads `SUFeedURL`, `https://github.com/schowave/browserdoor/releases/latest/download/appcast.xml`: the appcast attached to the newest release. Every release gets one (see 11.3), so the feed never answers 404.
- Sparkle's `automaticallyChecksForUpdates` follows the shared setting; `SUEnableAutomaticChecks` in Info.plist only spares the user Sparkle's question at the second launch.
- It shows the release notes, downloads the DMG, verifies its EdDSA signature against `SUPublicEDKey`, replaces the app in place and restarts it.
- Because Browserdoor runs in the menu bar, a scheduled check that finds an update brings the app to the front before Sparkle shows its window (gentle reminders).
- Sparkle's callbacks become `UpdateCycleEvent`s, and `UpdateStatus.after` decides the status:
  - A found update shows as "Update to Browserdoor X…", which opens Sparkle's window again. "Skip This Version" removes it; dismissing keeps it.
  - A check starts only while Sparkle can start one (`canCheckForUpdates`); otherwise it just brings its window back.
  - A check that ends without an answer (cancelled) clears "checking". An error shows only for a check the user asked for.
- Dev builds don't start Sparkle; "Check for Updates…" says they don't update themselves.

### 7.3 Scoop build (Windows)

- Once a day while "Check for updates automatically" is on (`state.json`), first 20 s after start, and when asked. Dev builds (`0.0.0`) never update.
- The newest version is the `version` of the Scoop manifest, `https://raw.githubusercontent.com/schowave/scoop-bucket/main/browserdoor.json`: exactly what `scoop update` would install, without GitHub's API rate limit.
- A newer version shows a dialog; "Later" suppresses the automatic notice for it. "Update" opens a PowerShell window that waits for Browserdoor to quit, runs `scoop update browserdoor` and starts Browserdoor again (`--background`); Browserdoor quits right after opening it. Without a Scoop installation the release page opens instead.

## 8. Launch and installation

### 8.1 Every launch

Every launch goes through `Startup` before any UI appears: carry over what earlier versions left (`Legacy`, see 8.5), register the running copy with LaunchServices (`LSRegisterURL`), maintain the installation (see 8.3), clean up after an update, then decide whether onboarding or reclaiming the default browser follows. Dev builds (`….dev`, also `swift run` without a bundle) get neither onboarding nor migration.

After an update, Browserdoor unregisters the path it last ran from (`lsregister -u`) if that path is gone (`brew cleanup` deleted it) or is another Cellar version of the formula (the restart after `brew upgrade` can come before the cleanup). Any other copy that still exists, such as a dev build, stays registered.

### 8.2 First launch

1. If Browserdoor is not the default browser, a dialog asks. On consent it calls `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` for http, and macOS shows its own confirmation.
2. Autostart is turned on (see 8.3).

The default browser is tied to the bundle ID, not the path.

### 8.3 Stable path and login item

Homebrew installs into a versioned Cellar directory, which `brew cleanup` deletes after an upgrade. Therefore:
- Running from a Cellar, Browserdoor creates `~/Applications/Browserdoor.app` on every launch as a symlink to `<brew prefix>/opt/browserdoor/Browserdoor.app`, or corrects an outdated symlink of its own. A real app at that location stays untouched.
- Autostart is a LaunchAgent, `~/Library/LaunchAgents/io.github.schowave.browserdoor.plist`, running `open -a` on the stable path: the symlink for Homebrew, the app itself otherwise (e.g. `/Applications/Browserdoor.app` from the DMG). It is repointed only when the app it starts is gone, so a second copy never takes it over. `SMAppService.mainApp` would remember the versioned path; such a login item from earlier builds is replaced on launch.

### 8.4 Restart after `brew upgrade`

A release build running from a Cellar watches `<brew prefix>/opt` (a `DispatchSource` on the folder). 3 s after it changes, and once at launch, it checks whether `opt/browserdoor/Browserdoor.app` now resolves to a different bundle that holds a `Contents/Info.plist` (`Installation.upgradedBundle`).
- If so, it quits. Only once quitting is certain (`willTerminate`) it starts a detached `/bin/sh` that waits for its PID to end and then runs `open -a` on the stable path (`Installation.restartArguments`).
- While the picker, the settings window or a modal dialog is open, it tries again every 10 s, so no link is lost.
- If `opt` itself is deleted or renamed, it watches the new folder. An uninstall (opt gone) or an unchanged link leaves it running.

### 8.5 Moving from Doorman

Up to 0.4.x the bundle ID was `io.github.schowave.doorman`, since 0.5.0 it is `io.github.schowave.browserdoor`. The first launch of a release build takes over what was stored under the old ID (`Legacy.moveIdentity`), before anything else, so the update check and the cleanup already see the moved values:
- A still running old instance is quit; it would write the old domain again and show a second menu bar icon.
- The user defaults of the old domain are copied into the new one (keys the new domain already has stay; global or registered values don't count), then the old domain is deleted. This carries over the onboarding state, the update check, the last bundle path and the menu bar position.
- `~/Library/Caches/io.github.schowave.doorman` is deleted.
- A LaunchAgent under the old label is replaced by one under the new label (`Legacy.moveLoginItem`). Without one, none is created.
- If the old ID was the `https` handler (read from `com.apple.launchservices.secure.plist`, because the old app is gone after `brew cleanup`), Browserdoor asks right away via `setDefaultApplication`, and macOS shows its confirmation. If the user declines, the notice stays in the menu.

### 8.6 Windows

- **Arguments**: `--background` (autostart: no window), `--quit` (ends the resident instance), `--list-targets` (prints the targets as `mise run targets` does on macOS, see 12; launches nothing), `--unregister` (ends the resident instance and removes the registration; Scoop's uninstaller calls it).
- **Resident instance**: the named mutex `Local\Browserdoor-resident` decides who it is. Every later launch connects to the pipe `\\.\pipe\Browserdoor-<user>` (local clients only), allows the resident instance into the foreground (`AllowSetForegroundWindow` with the pipe server's PID), sends its links as JSON and exits; it retries for 5 s while the resident instance starts. Links open the picker; a launch without links opens the settings.
- **Registration**, on every launch, under HKCU and without admin rights: the ProgIDs `BrowserdoorURL` and `BrowserdoorHTML`, `Software\Clients\StartMenuInternet\Browserdoor` with `Capabilities` (http, https; `.htm`, `.html`, `.xhtml`) and the `RegisteredApplications` entry. Windows is notified (`SHChangeNotify`) only if something changed.
- **Stable path**: the registration and the login item point at Scoop's `apps\browserdoor\current\browserdoor.exe`, which survives `scoop update`, not at the versioned folder.
- **First launch**: autostart on (`Run` value `Browserdoor` = `"<stable path>" --background`), then a dialog offers to open the Windows settings to choose Browserdoor as the default browser.
- **Dev builds** (debug) run as "Browserdoor Dev" with their own mutex, pipe and settings folder, and register nothing.

## 9. Architecture

Terms: see [GLOSSARY.md](GLOSSARY.md). The logic lives in a few deep modules in `BrowserdoorCore`, tested through their interface; the app (`Sources/Browserdoor`) renders and provides the adapters for the seams.

| Module (BrowserdoorCore) | Owns | Seam / adapter |
|---|---|---|
| `TargetCatalog` | Config file (incl. unreadable), Zen profile path, discovery, picker entries (derived from the rows: order, hiding, names, keys), edits (sort, rename, key, hide, default, extra apps, Zen profile; the state changes only through these), effective keys, saving. `Config` is only the file format with loading, merging on save and order | `BrowserEnvironment`: `SystemEnvironment` · `FakeEnvironment` |
| `Discovery` | Finding targets (allowlist, path filter, Zen version check, Chromium and Firefox profiles, extra apps) | `BrowserEnvironment` |
| `PickerSession` | Links, entries, selection, default row, profile badges, notice about an unreadable config, the hover rule; input → effects (close/open/copy/open settings). `PickerPlacement`: position at the mouse, kept within the visible screen. `LinkDisplay`: how the header names a link. `ProfileBadge`: which targets get a lettered circle, and its color | in-process |
| `LinkOpener` | Incoming items → allowed links; link + target → run the family's commands, then activate if the family requires it | `LaunchPort`: `SystemLaunchPort` · `RecordingPort` |
| `Startup` | Sequence of every launch: legacy (`Legacy`, ordered by version), registration, installation, cleanup after updates, onboarding or reclaiming the default browser; release build vs. dev build (`BundleIdentity`) | `StartupPort`: `SystemStartupPort` · Fake; `LegacyLoginItem`: `SMAppServiceLoginItem` · Fake |
| `Installation` | Homebrew facts, stable link, LaunchAgent, upgrade script, detecting an upgraded bundle | real file system (temp home in tests) |
| Browser families | `ZenBrowser`, `ChromiumFamily`, `FirefoxFamily`: per family the data location, targets and names; plus one target kind each (`ZenSpaceKind`, `ChromiumProfileKind`, `FirefoxProfileKind`, for simple browsers `AppKind`) with launch commands (running/cold) and activation. A new family is one file plus an entry in `Discovery.families`; `TargetID` formats and parses the IDs | `BrowserFamily` (discovery), `TargetKind` (launch) |
| `UpdatePolicy` | When to check, what to announce, Later, errors, displayed status. For the download build's updater: `UpdateStatus.after(UpdateCycleEvent)` | `ReleaseSource`: `GitHubReleaseSource` · Stub; `UpdatePreferences`: `UserDefaultsUpdatePreferences` · In-Memory |
| `TargetIcons` | Icon per target: the app icon, only Zen spaces differ (emoji → SVG → initial letter); starts the extraction once per Zen version | `ZenIconCache`, extractor: `unzip` · Fake |
| Parsers | `MozLz4`, `ZenSpaces`, `ZenProfile`, `ChromiumProfiles`, `FirefoxProfiles`, `WeblocParser` | in-process |

App: `AppDelegate` (main menu, onboarding dialog), `StatusMenu` (menu bar icon and menu), `About`, `PickerController` (shows the session directly, runs effects), `Settings` (window, binds the edits of `CatalogState`), `UpdateChecker` (dialogs and the upgrade script; in the download build Sparkle's updater), `UpgradeWatcher` (restarts after `brew upgrade`), `IconProvider` (loads NSImages; observable, so open windows reload the Zen icons as soon as they are extracted), adapters (`SystemEnvironment`, `SystemLaunchPort`, `SystemStartupPort`, `SMAppServiceLoginItem`).

### 9.1 Windows

`windows/core` has the same modules under the same names (Rust spelling): `catalog` (`TargetCatalog`, `CatalogState`), `discovery` behind `BrowserEnvironment`, `families` (Chromium, Firefox and Zen parsers and data locations), `picker` (`PickerSession`, keys), `opener` (`LinkOpener` behind `LaunchPort`), `link_display`, `badge`, `placement`, `update` (`UpdatePreferences`, versions), `url_policy`, `target_id`, `config`, `listing`. `windows/app` provides the adapters (`system::WinEnv`, `system::WinLaunch`) and the shell: `ipc` (resident instance), `registry`, `picker` and `settings` (windows and commands), `tray`, `updates`, `icons` (the `.exe` icon as PNG), `views` (what the pages get, mirrored in `windows/ui/src/lib/api.ts`).

## 10. Build and distribution

### 10.1 Tooling

- mise: `mise.toml` pins `actionlint`, `shellcheck` and `swiftformat`. Swift comes from Xcode or the Command Line Tools, because Browserdoor needs the macOS SDK.
- The tasks are POSIX shell scripts in `.mise/tasks/` with `#MISE` header lines (`mise tasks` lists them); shared settings come from `_lib.sh`. They also run without mise, which the Homebrew formula relies on.
- `mise run setup` gets a fresh clone ready (pinned tools, Swift packages); `mise run check` (= `ci`) runs everything CI's `test` job runs (see 11.1). `fmt` and `build` are aliases of `format` and `app`.

### 10.2 Builds

- **Dev build** (`mise run app` → `build/Browserdoor.app`): Info.plist, app icon (`Resources/Icon/AppIcon.icns`, generated from `AppIcon.svg` with `mise run icons` and checked in) and menu bar glyph (`MenuBarIcon.svg`) come from `Resources/`. Signed ad hoc. The version comes from `VERSION` or the latest `v*` tag. Bundle ID `io.github.schowave.browserdoor.dev` and name "Browserdoor Dev", so it shares neither the default browser, settings, login item nor menu bar with the installed app. Only `install` (Homebrew) and the release's `dmg` job build the real ID, with `DEV_BUILD=0`.
- **Homebrew build**: what the formula builds (see 10.3). It contains no updater of its own and fetches no package.
- **Download build** (`SPARKLE=1 mise run app` → `build/sparkle/Browserdoor.app`):
  - `Package.swift` adds Sparkle (pinned with `exact:`) and the compile condition `SPARKLE` only when `BROWSERDOOR_SPARKLE=1` is set. `Package.resolved` is not checked in, because it would make every build fetch Sparkle.
  - The task builds in `.build/sparkle`, embeds `Sparkle.framework` under `Contents/Frameworks` (rpath `@executable_path/../Frameworks`) and adds `SUFeedURL`, `SUEnableAutomaticChecks` and, from `SPARKLE_PUBLIC_KEY`, `SUPublicEDKey` to Info.plist.
  - `mise run dmg [identity]` signs it inside out with the hardened runtime (Sparkle's XPC services, `Autoupdate`, `Updater.app`, the framework, the app) and packs `build/Browserdoor.dmg` with a link to `/Applications`. Without an identity it signs ad hoc.
  - `mise run check-dmg`, part of `ci`, builds it and its DMG ad hoc.

### 10.3 Homebrew formula

- The formula `browserdoor` lives in the tap `schowave/homebrew-tap` under `Formula/`.
- On macOS 15 and later users get a bottle (Apple Silicon and Intel) and need no Xcode. Otherwise the formula builds from the release tarball (`depends_on xcode: 16` for building) and calls `.mise/tasks/install` directly with `PREFIX`, `VERSION`, `SWIFT_BUILD_FLAGS=--disable-sandbox` and `BIN_APP_PATH` (the stable `opt` path for `bin/browserdoor`, which uses `open -a`).
- The template `packaging/homebrew/browserdoor.rb` has `@URL@`, `@VERSION@` and `@SHA256@`; `render-formula` fills them in, `check-formula` checks the result. Only the release workflow writes the `bottle do` block. The formula test also checks the app's code signature, so relocating a bottle can't damage it.

### 10.4 Homepage

`site/` holds the homepage. `mise run site` (part of `ci`) assembles it in `build/site` with the shared images, gives stylesheet and script a version from their content (`style.css?v=…`) and checks that every local reference exists. `pages.yml` deploys it to `https://schowave.github.io/browserdoor/` when one of its sources changes on `main`. Its download button links `releases/latest/download/Browserdoor.dmg`.

### 10.5 Windows

- mise also pins Rust, Node and uv. Tasks: `windows-core` (format, lint and test `windows/core`; part of `check`, runs on any OS), `windows-check` (everything, on Windows: core, UI check and build, app lint and tests, release build), `windows-smoke <exe>` (see 11.5), `windows-icons` (renders `windows/app/icons` from `Resources/Icon`), `render-scoop`, `release-windows`.
- The build is a single `browserdoor.exe` (the pages are embedded); the release zips it with `LICENSE` per architecture. The version comes from `BROWSERDOOR_VERSION` at build time.
- **Scoop**: the manifest template `packaging/scoop/browserdoor.json` (`@VERSION@`, `@SHA256_X64@`, `@SHA256_ARM64@`) becomes `browserdoor.json` in `schowave/scoop-bucket`. It adds a Start menu shortcut and the `browserdoor` command; its uninstaller runs `--unregister` on uninstall and `--quit` before an update.

## 11. CI and release

### 11.1 CI

`ci.yml`, on pushes to `main` and pull requests; a required check on `main`.
- Job `test` (macOS 26): `mise run setup`, then `mise run check`: lint, unit tests, tests of the release scripts, docs and strings checks, the homepage, the Homebrew app bundle and the download build's DMG.
- Job `formula` (macOS 15, whose Swift is the oldest the bottles are built with): renders the formula for a local tarball, builds it as a bottle (`.mise/tasks/bottle`), pours it again (checks `poured_from_bottle`), runs `brew test` and `brew audit --strict`: the path users take.
- `retry.yml`: when a run of CI, Release, Auto release, CodeQL or Pages fails because GitHub had no runner for a job ("not acquired by Runner") or lost it midway, its failed jobs start again, at most twice. Other failures are left alone.

### 11.2 Release

`mise run release vX.Y.Z` runs `check`, pushes an annotated tag, waits for `release.yml` and puts the version's CHANGELOG section on top of the release notes. It fails if the release, the tap update, marking the release as latest or the DMG check failed; failed bottles only give a warning.

`release.yml` runs on a `v*` tag or when `auto-release.yml` calls it. Every job is safe to rerun.
1. `release`: tests, builds the app, checks the formula template and creates the GitHub release (if none exists) with `--latest=false`.
2. `bottle` (macOS 15 on arm64 and on Intel; there are no macOS 14 runners) builds a bottle each and attaches it with its JSON. A rerun reuses attached bottles, so the sha256 values in the tap stay valid.
3. `dmg`, next to the bottles: the download build (see 11.3).
4. `tap`: renders the formula, merges the bottles' `bottle do` block (`brew trust`, `brew bottle --merge`) and pushes it to the tap (secret `TAP_GITHUB_TOKEN`). With some bottles missing it still updates, those Macs build from source; with none it fails and leaves the tap unchanged.
5. `latest`: marks the release as latest, only after `dmg` and `tap`, because the update checks of both builds follow `releases/latest`.
6. `verify`: `mise run check-release` (see 11.3), when the DMG was built in this run.

### 11.3 Download build in the release

- **`dmg` job**: builds the download build with `DEV_BUILD=0`, imports the Developer ID certificate into a temporary keychain and runs `dmg` with it. It notarizes the DMG (`notarytool` with an App Store Connect API key; anything but `Accepted` prints Apple's log and fails), staples it and checks it with `spctl`.
- **Appcast**: `sign_update` signs the DMG with the EdDSA key, and `mise run appcast <tag> <dmg-url> <sign_update output>` writes the appcast with the tag's CHANGELOG section as HTML; a tag without one (a patch release from `auto-release.yml`) links its release page instead.
- **Assets**, in this order: `Browserdoor-<version>.dmg` (which the appcast names), the same file as `Browserdoor.dmg` (so `releases/latest/download/Browserdoor.dmg` is always the newest), `appcast.xml`. A release that already has `appcast.xml` is left alone on a rerun.
- **Secrets**: `DEVELOPER_ID_CERT_P12` (base64), `DEVELOPER_ID_CERT_PASSWORD`, `NOTARY_API_KEY` (the `.p8` text), `NOTARY_API_KEY_ID`, `NOTARY_API_ISSUER`, `SPARKLE_PRIVATE_KEY`, and the variable `SPARKLE_PUBLIC_KEY`. While one is missing the job skips itself with a notice.
- **Without a DMG** (a step failed or a secret is missing), the release gets the previous release's `appcast.xml` and `Browserdoor.dmg`, so download installs stay on the previous version and the download link keeps working. To build the DMG after all, delete that appcast and rerun the job. The DMG doesn't block the tap, nor the tap the DMG.
- **`check-release <tag>`** checks a published release as users get it: the appcast names the version and the versioned DMG; both DMGs are the same file, of the appcast's length; the quarantined DMG and the app inside pass Gatekeeper as notarized and the ticket is stapled; version, bundle ID, `SUFeedURL` and `SUPublicEDKey` (against `SPARKLE_PUBLIC_KEY`, if set) are right; the EdDSA signature is valid for the app's public key (`_ed25519-verify.swift`, CryptoKit, so no private key is needed). For the latest release, `releases/latest/download/appcast.xml` and `…/Browserdoor.dmg` must be that release's.

### 11.4 Dependencies

- **Renovate** (GitHub App, `renovate.json`):
  - Once a week (Monday before 6 am): one PR with all patch, minor, pin and digest updates (GitHub Actions are pinned to digests) and one for the mise tools, so a new lint rule doesn't block the other updates. Each major update gets its own PR.
  - Updates are taken only once they are 7 days old (`minimumReleaseAge`).
  - Every PR, majors included, merges by GitHub's auto-merge (`platformAutomerge`) once CI is green.
- **Auto-release** (`auto-release.yml`):
  - A merge by `renovate[bot]` to `main` creates the next patch tag (`next-patch-version`), but only if the app changed since the last tag (`Sources/`, `Resources/`, `Package.swift`/`.resolved`; `app-changed-since-release`). Updates of CI or lint tools alone make no release.
  - The tag is created through the API; if `HEAD` already carries a tag, nothing happens. A `concurrency` group prevents parallel releases.
  - Tags created with the `GITHUB_TOKEN` start no workflows, so the job calls `release.yml` directly.
  - Without any `v*` tag nothing happens; the first release is made by hand.

### 11.5 Windows

- `ci.yml`, job `windows` (Windows, x64): `windows-check`, then `windows-smoke` on the release build: `--list-targets` must find Microsoft Edge; a resident instance starts; a second launch with a link hands it over and exits within 10 s, leaving one process; the registration and the login item exist; `--quit` ends it; `--unregister` removes the registration. A screenshot and the log are kept as an artifact.
- `ci.yml`, job `parity`: `check-parity` fails if the domain changed on one side only (`Sources/BrowserdoorCore` or `windows/core/src`) without a `Parity: …` line in a commit message saying why.
- `zen-contract.yml`: weekly and when a Zen parser or the contract changes; on macOS, Windows x64 and Windows ARM against the newest Zen (see 12).
- `release-windows.yml`, on a `windows-v*` tag (`mise run release-windows windows-vX.Y.Z` checks `windows/CHANGELOG.md`, tags and waits): builds and smoke-tests x64 and arm64 on Windows runners, creates the release `windows-vX.Y.Z` with both zips and their SHA-256 and the version's section of `windows/CHANGELOG.md`, **never as latest** (the macOS update checks follow `releases/latest`), then pushes the rendered manifest to `schowave/scoop-bucket` (secret `TAP_GITHUB_TOKEN`, which needs contents:write there too). Safe to rerun.

## 12. Tests

The core (`BrowserdoorCore`) is tested through its modules' interfaces with Swift Testing, against fakes for the seams in 9 and fixtures for the file formats (`Tests/BrowserdoorCoreTests`). The release scripts have their own tests (`mise run test-scripts`). The UI is tested by hand; `mise run targets` shows what discovery finds on the real Mac and the command each target would run.

The Windows domain (`windows/core`) is tested the same way with `cargo test`, against a fake Windows (`BrowserEnvironment`) and the fixtures. `fixtures/` is shared by both test suites: `fixtures/zen/zen-sessions.jsonlz4` was written by a real Zen, and both parsers must read the spaces in `fixtures/zen/spaces.json` from it. The **Zen contract test** (`contract/zen_contract.py`, `uv run`) drives a real Zen on a throwaway profile through Marionette: it creates two spaces, checks the session file's `spaces[]` fields, a cold start with `--space <uuid>`, and hand-overs to the running Zen by UUID and by name; CI then reads the session file Zen wrote with Browserdoor's parser. On Windows, `browserdoor.exe --list-targets` shows what discovery finds and the command each target would run.
