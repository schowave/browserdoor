# Browserdoor — Specification v1

Browserdoor is a macOS link picker in the style of Browserosaurus. It is registered as the default browser. When you click a link, a panel appears at the mouse position. In it you choose the target: a **Zen space**, a **Chromium profile**, a **Firefox profile** or another installed browser.

## 1. Goals and non-goals

**v1 includes**
- Default browser for `http`, `https`, `.html` and `.webloc`
- Panel with a mixed target list: Zen spaces, Chromium browsers × profiles, Firefox profiles, other browsers
- Configuration as a JSON file
- Installation via a Homebrew formula from a dedicated tap

**Not in v1**
- Rule engine (à la Finicky)
- Bypass via a modifier key
- Settings window (GUI)
- Code signing and cask
- Editable URL in the panel
- `mailto:`
- Multiple Zen profiles
- Firefox containers as separate targets
- Safari profiles (Safari has no CLI for them)

## 2. Platform and technology

- Swift 6, SwiftUI and AppKit, **macOS 14+**.
- Built with Swift Package Manager. `mise run app` builds `Browserdoor.app` from it (see 9). The build uses Xcode 16 (Swift 6).
- The app runs permanently in the background:
  - `LSUIElement`, so no Dock icon
  - Menu bar icon (a door ajar as a template image, `NSStatusItem`; the menu is rebuilt every time it opens, so the status lines are current)
  - Autostart via a LaunchAgent (see 7)
- License: MIT. The repo is public on GitHub.

## 3. Targets

A **target** is an entry in the panel. Every target has a stable `id`, a display name, an icon and a method for opening.

| Kind | ID scheme | Opening |
|---|---|---|
| Zen space | `zen:{<uuid>}` | Zen is running: `<Zen.app>/Contents/MacOS/zen --space "{uuid}" <url>` per URL. Zen is not running: `open -a <Zen.app> --args --space "{uuid}" <url…>` |
| Zen without workspace support | `app:app.zen-browser.zen` | like a regular browser |
| Chromium profile | `chromium:<bundleId>:<profileDir>` | `open -na <App> --args --profile-directory=<dir> <url…>` |
| Firefox profile | `firefox:<bundleId>:<profilePath>` | `open -na <App> --args --profile <dir> <url…>` |
| Regular browser | `app:<bundleId>` | `NSWorkspace.open(urls, withApplicationAt:)` |

### 3.1 Zen

- **Finding the app**: via the bundle ID `app.zen-browser.zen` among the https handlers (see 3.4, path filter).
- **Profile**: Browserdoor reads `~/Library/Application Support/zen/profiles.ini`. The `Default=` line of the `[Install…]` section decides. If it does not exist, the profile with `Default=1` applies. In the configuration, `zen.profilePath` overrides the profile.
- **Workspaces**: They are stored in `<profile>/zen-sessions.jsonlz4`.
  - Format: mozLz4. The file starts with the magic `mozLz40\0` (8 bytes), followed by the size as uint32 LE, followed by a raw LZ4 block payload.
  - From it, Browserdoor reads `spaces[]`, each with `uuid`, `name`, `icon` and `theme.gradientColors`.
  - The file is read again **every time the panel opens**.
- **Icons**: `icon` is a `chrome://browser/skin/zen-icons/selectable/<name>.svg` URL, an emoji or empty.
  - The SVGs are in `<Zen.app>/Contents/Resources/browser/omni.ja` (a zip) under `chrome/browser/skin/classic/browser/zen-icons/selectable/`.
  - They are extracted once per Zen version to `~/Library/Caches/io.github.schowave.browserdoor/zen-icons/<version>/`.
  - Fallback: If the icon is an emoji, it is shown directly. Otherwise the initial letter appears on the theme color.
- **Version check**: `--space` exists from Zen 1.24 on (PR zen-browser/desktop#15074). If the version is older (`CFBundleShortVersionString`) or the file cannot be read, Zen appears as a single `app:` target.
- **Zen is not running**: Browserdoor starts Zen via LaunchServices (`open -a … --args --space …`), so Zen does not become a child process of Browserdoor. Zen keeps the space for its own launch (`zen.workspaces.cmdline-initial-workspace`).
- **Zen is running**: The direct call hands over to the running instance and returns immediately (tested with 1.24.1b). Then Browserdoor activates Zen.

### 3.2 Chromium browsers

- **Supported browsers** (`bundleId` → data directory under `~/Library/Application Support/`):
  - `com.google.Chrome` → `Google/Chrome`
  - `com.google.Chrome.beta` → `Google/Chrome Beta`
  - `com.google.Chrome.canary` → `Google/Chrome Canary`
  - `com.brave.Browser` → `BraveSoftware/Brave-Browser`
  - `com.microsoft.edgemac` → `Microsoft Edge`
  - `com.vivaldi.Vivaldi` → `Vivaldi`
  - `org.chromium.Chromium` → `Chromium`
- **Profiles**: They are stored in `<datadir>/Local State` under `profile.info_cache`, as a mapping `<profileDir>` → `{name}`.
- If there is **exactly one** profile, the browser appears as a single entry without a profile name. The target ID scheme then stays `chromium:<bundleId>:<profileDir>`.

### 3.3 Firefox

- **Supported**: `org.mozilla.firefox` with the data directory `~/Library/Application Support/Firefox`. Developer Edition and Nightly share this directory and stay single `app:` entries; otherwise every profile would be listed three times.
- **Profiles**: They are stored in `profiles.ini` in the `[ProfileN]` sections (`Name`, `Path`, `IsRelative`). `profilePath` in the target ID is `Path`, as Firefox stores it.
  - Since Firefox 138, the profile manager stores a profile group in `Profile Groups/<StoreID>.sqlite` (table `Profiles`: `id`, `path`, `name`, …; `path` relative to the data directory). `profiles.ini` contains only one profile of it, marked with `StoreID=`. It is replaced by the profiles of the group.
  - The database runs in WAL mode. Browserdoor copies the database and `-wal` to a temporary directory and reads them there, so new profiles are visible immediately and Firefox's files stay untouched.
  - Order: first the profiles that an `[Install…]` section names as `Default=`, then the others by section number or `id`.
  - The empty `default` profile that Firefox creates next to `default-release` is dropped, unless an installation uses it.
- If there is **at most one** profile, Firefox stays a single `app:` target.
- **Opening**: Always via `open -na`, so Firefox does not become a child process of Browserdoor. If the profile is already running, the new instance hands the URLs to the running one and quits (tested with Firefox 160). Otherwise Firefox starts with this profile.

### 3.4 Other browsers

- The basis is all apps that can open `https` (`NSWorkspace.urlsForApplications(toOpen:)`).
- **Path filter**: Only apps under `/Applications`, `~/Applications` or `/System` count. Copies in caches or snapshots (Playwright, Puppeteer, …) are dropped. If a bundle ID occurs more than once, the first allowed copy wins.
- **Allowlist**: Only known browsers are shown (`KnownBrowsers`, analogous to Browserosaurus), plus the bundle IDs from `extraApps` in the configuration. Otherwise LaunchServices also lists terminals, web app wrappers, Finicky/Browserosaurus etc.
- Excluded are Browserdoor itself, and Zen, the Chromium browsers and Firefox when 3.1 to 3.3 already cover them.

### 3.5 Allowed URLs

URLs reach the browsers as command-line arguments. Therefore Browserdoor lets only `http`, `https` and `file` through (`URLPolicy`); everything else, such as `--remote-debugging-port=…` or `javascript:`, is discarded. From `.webloc` files only `http` and `https` are accepted, so a downloaded file cannot open a local file. The check applies on receipt and again when building the launch commands.

If `zen.profilePath` is set, every Zen call additionally gets `--profile <path>`, so `--space` reaches the instance with this profile.

## 4. Panel (UI)

- A floating, borderless `NSPanel` at the mouse position. It is constrained to the visible screen area.
- **Content**:
  - at the top the link (`LinkDisplay`): the host in bold, path, query and fragment in gray. The host is shown as Foundation parses it, so non-ASCII hosts appear in Punycode (`xn--…`) and look-alike domains stand out; user info (`https://bank.com@evil.io`) is not shown. A `file` link shows its file name in bold and its folder in gray (`~` for the home folder). For multiple links "N links", with every link in the tooltip.
  - below it the list of targets: icon, name, hotkey. The default target carries a `↩` mark, even while another row is selected. The selected row is drawn like a selected menu item (system selection color, white text).
  - Targets of the same app (Chromium and Firefox profiles, several installs) get a small lettered circle on the icon (`ProfileBadge`): the first letter of the name, in a color picked from a fixed palette by a stable hash of the target ID. Zen spaces and apps listed only once get none.
  - Button "Copy URL"
  - If every target is hidden: "No visible targets" and a "Settings…" button.
- **Controls**:
  - An entry's hotkey opens that target.
  - ↑/↓ and Tab/⇧Tab move the selection, Home/End jump to the first/last entry, Enter opens the selection. The default target is preselected, otherwise the first entry.
  - Hovering selects a row only once the mouse has moved (2 pt) from where it was when the panel opened, so a pointer that happens to rest on a row does not replace the default.
  - Esc or a click outside closes the panel.
  - ⌘C copies the URL(s). ⌘, closes the panel and opens the settings on the Targets tab.
  - Every row is a button for VoiceOver, with its name as label, its key and the `↩` mark as hint, and the selected state.
- **Hotkeys**: Without configuration, `1`–`9`, then `0` apply in list order. The configuration can override them per target.
- **Multiple links**: If more URLs arrive while the panel is open, they are collected. A selection opens all of them.

## 5. Configuration

The file is at `~/.config/browserdoor/config.json`. It is optional; if it is missing, the defaults apply. Unknown fields are ignored.

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

- **`order`**: These targets come first, in the given order. All others follow in discovery order:
  1. Zen spaces in Zen's order
  2. Chromium browsers
  3. Firefox profiles
  4. other browsers alphabetically
- **`extraApps`**: Bundle IDs of apps that are not known browsers but should still appear as a target.
- **`targets.<id>.label`**: Overrides the display name. In the config file it is also the readable name next to the UUID.
- The file is normally maintained through the settings window (see 6). It rewrites the file on every change (sorted keys, stable diffs); settings of targets that are not currently discovered are kept.

## 6. Menu bar, settings, updates

**Menu bar icon** (`StatusMenu`): the door as a template image. While Browserdoor isn't the default browser, it carries a dot (part of the template image, so macOS tints it like the door); the state is checked when the menu opens, when the app becomes active, after "Make Default Browser" and every 60 s. The icon can be hidden with "Show in menu bar" in the settings or by ⌘-dragging it out of the menu bar; both are the same setting, which macOS keeps in the user defaults with the icon's position. Opening Browserdoor again then shows the settings.

**Menu bar menu** (rebuilt every time it opens, only cheap queries):
- "About Browserdoor" (standard About panel with a link to the repository and the license); with ⌥ "Report an Issue…", which opens GitHub's bug form with the Browserdoor and macOS versions filled in (`IssueReport`) and nothing else
- "Open Link from Clipboard…": shows the picker for the links on the clipboard (URL objects and every word of the text that parses as a URL, filtered like any incoming link). Enabled only if the clipboard holds a web link; from macOS 15.4 the system answers that without Browserdoor reading the clipboard (no privacy notice), before that any text enables it.
- "Make Default Browser" with a warning sign, only when needed
- "Update to Browserdoor X…" if an update is known, else "Check for Updates…"
- "Settings…" (⌘,); with ⌥ "Show Configuration in Finder"
- "Quit Browserdoor"

**Settings window** (an `NSWindow` with a toolbar tab per pane, SwiftUI inside; also opens when Browserdoor is started again while the app is running, e.g. via `browserdoor`). The window takes the selected pane's title and size. General and Advanced have a fixed size; Targets can be resized and keeps its size (user defaults).
- *General:* default browser status and button, "Start at login" (LaunchAgent; the checkmark shows only whether it exists, not whether it is blocked in System Settings; an error shows below the switch), "Show in menu bar", updates.
- *Targets:* all discovered targets with icon (and profile badge, see 4), sortable by dragging, can be shown/hidden, renamable, star for the default target. The key field is a recorder: click it and press a key; Esc cancels, ⌫ removes the custom key. Without a custom key it shows the automatic key in gray. If another target showed that key in the picker, it loses it, and a note under the list says so for a few seconds. **+** adds apps via a selection dialog (`extraApps`; they appear even without an https registration), **−** removes such an app. A right-click on a target offers Rename (focuses its name), Make Default Target / Remove as Default Target, Hide in Picker / Show in Picker and, for added apps, Remove App. For VoiceOver the checkbox, name, key and star carry labels; the drag handle and icon are hidden.
- *Advanced:* Zen profile, show the configuration file in Finder.
- The picker's ⌘, and its empty-state button open the Targets pane.
- An invisible main menu provides About, ⌘C/⌘V/⌘A, ⌘W, ⌘M, ⌘H and ⌘, for the window.

**Updates:** `HEAD https://github.com/schowave/browserdoor/releases/latest`; the redirect to `…/releases/tag/<tag>` names the newest release (excluding drafts and pre-releases). The API (`api.github.com`) is deliberately not used, because without a token it allows only 60 requests per hour and IP. The automatic check runs at most once per 24 h (can be turned off) and on request. If the version is newer (`AppVersion` comparison; dev builds, version `0.0.0`, are never offered updates), a dialog appears. "Update in Terminal" opens a `.command` script: `brew update && brew upgrade browserdoor`, quit the old Browserdoor, start the new one via `browserdoor`. Without a Homebrew installation, the release page is offered instead. "Later" suppresses the automatic notice for this version. This is Browserdoor's only network access.

**Language:** English and German according to the system language (`Resources/Localization/*.lproj/Localizable.strings`, key = English text). `mise run check-strings` checks that every key is translated.

## 7. First launch

Every launch goes through `Startup` before any UI appears: carry over what earlier versions left (`Legacy`), register with LaunchServices, maintain the installation, clean up after an update, then decide whether onboarding or reclaiming the default browser follows. Dev builds (`….dev`, also `swift run` without a bundle) get neither onboarding nor migration.

On the first launch of a release build, the following happens:
1. The app registers with LaunchServices (`LSRegisterURL`).
2. If Browserdoor is not the default browser, a dialog appears. On consent the app calls `NSWorkspace.setDefaultApplication(at:toOpenURLsWithScheme:)` for http. macOS then shows its own confirmation dialog.
3. Autostart is enabled (LaunchAgent, see below).

**Stable across `brew upgrade`:** Homebrew installs into a versioned Cellar directory, which `brew cleanup` deletes after an upgrade. Therefore:
- If Browserdoor runs from a Cellar, it creates `~/Applications/Browserdoor.app` on every launch as a symlink to `<brew prefix>/opt/browserdoor/Browserdoor.app` (or corrects an outdated symlink of its own). A real app at that location stays untouched.
- The autostart is a LaunchAgent `~/Library/LaunchAgents/io.github.schowave.browserdoor.plist` that runs `open -a ~/Applications/Browserdoor.app`. `SMAppService.mainApp` would remember the versioned path; such a login item from earlier builds is removed and replaced on launch.
- The default browser is tied to the bundle ID and is therefore independent of the path; every launch registers the running copy again (`LSRegisterURL`).
- **Bundle ID change** (up to 0.4.x `io.github.schowave.doorman`, since 0.5.0 `io.github.schowave.browserdoor`): The first launch of a release build takes over what was stored under the old ID (`Legacy.moveIdentity`), before anything else, so the update check and the cleanup already see the taken-over values:
  - A still running old instance is quit (otherwise it would write the old domain again and show two menu bar icons).
  - The UserDefaults of the old domain are copied into the new one (keys already present in the own domain stay; global or registered values do not count), then the old domain is deleted. This carries over the onboarding status, the update check, the last bundle path and the menu bar position.
  - `~/Library/Caches/io.github.schowave.doorman` is deleted.
  - A LaunchAgent under the old label is replaced by one under the new label (`Legacy.moveLoginItem`). Anyone who had none gets none.
  - If the old ID was registered as the `https` handler (read from `com.apple.launchservices.secure.plist`, because the old app no longer exists after `brew cleanup`), Browserdoor asks immediately via `setDefaultApplication`, and macOS shows the confirmation dialog. If the user declines, the notice stays in the menu.
- After an update, Browserdoor unregisters from LaunchServices the path of the version it last ran from (`lsregister -u`), if that path no longer exists (`brew cleanup` deleted it). If it still exists (e.g. a dev build), it stays.

## 8. Architecture

Terms: see [GLOSSARY.md](GLOSSARY.md). The logic lives in a few deep modules in `BrowserdoorCore`, tested through their interface; the app (`Sources/Browserdoor`) renders and provides the adapters for the seams.

| Module (BrowserdoorCore) | Owns | Seam / adapter |
|---|---|---|
| `TargetCatalog` | Config file (incl. unreadable), Zen profile path, discovery, picker entries (derived from the rows: order, hiding, names, keys), edits (sort, rename, key, hide, default, extra apps, Zen profile; the state changes only through these), effective keys, saving. `Config` is only the file format with loading, merging on save and order | `BrowserEnvironment`: `SystemEnvironment` · `FakeEnvironment` |
| `Discovery` | Finding targets (allowlist, path filter, Zen version check, Chromium and Firefox profiles, extra apps) | `BrowserEnvironment` |
| `PickerSession` | Links, entries, selection, default row, profile badges, notice about an unreadable config, the hover rule; input → effects (close/open/copy/open settings). `PickerPlacement`: position at the mouse, kept within the visible screen. `LinkDisplay`: how the header names a link. `ProfileBadge`: which targets get a lettered circle, and its color | in-process |
| `LinkOpener` | Incoming items → allowed links; link + target → run the family's commands, then activate if the family requires it | `LaunchPort`: `SystemLaunchPort` · `RecordingPort` |
| `Startup` | Sequence of every launch: legacy (`Legacy`, ordered by version), registration, installation, cleanup after updates, onboarding or reclaiming the default browser; release build vs. dev build (`BundleIdentity`) | `StartupPort`: `SystemStartupPort` · Fake; `LegacyLoginItem`: `SMAppServiceLoginItem` · Fake |
| `Installation` | Homebrew facts, stable link, LaunchAgent, upgrade script | real file system (temp home in tests) |
| Browser families | `ZenBrowser`, `ChromiumFamily`, `FirefoxFamily`: per family the data location, targets and names; plus one target kind each (`ZenSpaceKind`, `ChromiumProfileKind`, `FirefoxProfileKind`, for simple browsers `AppKind`) with launch commands (running/cold) and activation. A new family is one file plus an entry in `Discovery.families`; `TargetID` formats and parses the IDs | `BrowserFamily` (discovery), `TargetKind` (launch) |
| `UpdatePolicy` | When to check, what to announce, Later, errors, displayed status | `ReleaseSource`: `GitHubReleaseSource` · Stub; `UpdatePreferences`: `UserDefaultsUpdatePreferences` · In-Memory |
| `TargetIcons` | Icon per target: the app icon, only Zen spaces differ (emoji → SVG → initial letter); starts the extraction once per Zen version | `ZenIconCache`, extractor: `unzip` · Fake |
| Parsers | `MozLz4`, `ZenSpaces`, `ZenProfile`, `ChromiumProfiles`, `FirefoxProfiles`, `WeblocParser` | in-process |

App: `AppDelegate` (main menu, onboarding dialog), `StatusMenu` (menu bar icon and menu), `About`, `PickerController` (shows the session directly, runs effects), `Settings` (window, binds the edits of `CatalogState`), `UpdateChecker` (dialogs, opens the upgrade script), `IconProvider` (loads NSImages; observable, so open windows reload the Zen icons as soon as they are extracted), adapters (`SystemEnvironment`, `SystemLaunchPort`, `SystemStartupPort`, `SMAppServiceLoginItem`).

## 9. Build, distribution, CI

- **Tooling:** mise. `mise.toml` pins `actionlint`, `shellcheck` and `swiftformat`. Swift itself comes from Xcode or the Command Line Tools, because Browserdoor needs the macOS SDK.
- **Tasks:** They live in `.mise/tasks/` as executable shell scripts with `#MISE` header lines and replace the former Makefile: `test`, `app`, `install`, `run`, `lint`, `format`, `render-formula`, `check-formula`, `next-patch-version`, `app-changed-since-release`, `test-scripts`, `bottle`, `ci`, `clean`, `check-docs`, `targets`, `release`. Shared settings come from `_lib.sh`. The scripts also run without mise.
- `mise run app` produces `build/Browserdoor.app`. Info.plist, app icon (`Resources/Icon/AppIcon.icns`) and menu bar glyph (`MenuBarIcon.svg`, template image) come from `Resources/`. The `.icns` is generated from `AppIcon.svg` with `mise run icons` and checked in. Signing is ad hoc. The version comes from `VERSION` or the latest `v*` tag. Such developer builds get the bundle ID `io.github.schowave.browserdoor.dev` and the name "Browserdoor Dev", so they do not share the default browser, settings, login item and menu bar with the installed app. Only `install` (Homebrew) builds the real ID with `DEV_BUILD=0`.
- **Homebrew:**
  - The formula `browserdoor` lives in the tap `schowave/homebrew-tap` under `Formula/`.
  - Users on macOS 15 and later get a bottle (Apple Silicon and Intel) and then need no Xcode. Without a matching bottle, the formula builds from the release tarball (`depends_on xcode: 16` for building) and calls `.mise/tasks/install` directly, i.e. without mise, with `PREFIX`, `VERSION`, `SWIFT_BUILD_FLAGS=--disable-sandbox` and `BIN_APP_PATH` (the stable `opt` path for `bin/browserdoor`, which uses `open -a`).
  - The template `packaging/homebrew/browserdoor.rb` uses `@URL@`, `@VERSION@` and `@SHA256@`. `render-formula` fills in the values, `check-formula` checks the result. Only the release workflow writes the `bottle do` block into it. The formula test also checks the app's code signature, so that a bottle does not damage it when relocating.
- **CI** (`ci.yml`, macOS runner):
  - Job `test`: `mise run ci` with lint, unit tests, tests of the release scripts, app bundle and formula check.
  - Job `formula`: renders the formula for a local tarball, builds it as a bottle with `.mise/tasks/bottle`, runs `brew audit --strict`, reinstalls the bottle (checks `poured_from_bottle`) and runs `brew test`, i.e. the path users take.
- **Release** (`release.yml`): runs on a `v*` tag or when another workflow calls it (`workflow_call`). Sequence: test, build the app, create the GitHub release (if none exists yet). Then `macos-15` (arm64) and `macos-15-intel` each build a bottle (there are no runners for macOS 14 anymore) and attach it to the release. Finally the formula with the `bottle do` block (`brew bottle --merge`, preceded by `brew trust`) goes into the tap. If one bottle fails, the tap is still updated, only with fewer bottles. If all fail, the tap stays unchanged. Each bottle's JSON sits next to it in the release. A rerun reuses existing bottles, so the sha256 values in the tap stay valid. This requires the secret `TAP_GITHUB_TOKEN`.
- **Renovate** (GitHub App, `renovate.json`):
  - Once a week (Monday before 6 am), one PR for GitHub Actions (pinned to digests) and one for the mise tools. Separate, so a new lint rule does not also block the Action updates.
  - Updates are taken only once they are 7 days old (`minimumReleaseAge`).
  - Renovate creates majors only after approval in the Dependency Dashboard.
  - Renovate merges the PRs itself as soon as CI is green.
- **Auto-release** (`auto-release.yml`):
  - A merge by `renovate[bot]` to `main` creates the next patch tag (`next-patch-version`), but only if the app has changed since the last tag (`Sources/`, `Resources/`, `Package.swift`/`.resolved`; `app-changed-since-release`). Updates that affect only CI or lint tools produce no release.
  - The tag is created via the API; if `HEAD` already carries a tag, nothing happens. A `concurrency` group prevents parallel releases.
  - Tags created with the `GITHUB_TOKEN` do not start workflows themselves, so the job calls `release.yml` directly.
  - Without an existing `v*` tag nothing happens; the first release is created by hand.

## 10. Tests

The following parts of the core are covered:
- MozLz4 decoder, against fixtures (compressed file → expected JSON)
- Parsers for `zen-sessions`, `profiles.ini` and `Local State`
- Webloc parser
- Ordering, hiding, labels and hotkey assignment of the configuration
- Discovery: order, allowlist, `extraApps`, path filter, Zen fallbacks
- Launch command per target kind, including Zen cold start
- Key handling in the panel (`PickerKeys`), including Caps Lock
- Decision about the symlink in `~/Applications` and rewriting the LaunchAgent
- Release scripts (`test-scripts`): next patch tag, app change since the last release, URL argument of `render-formula`

The UI is tested manually.
