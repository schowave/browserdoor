# Glossary

Domain terms used in Browserdoor's code, docs and reviews. Module names in `code` live in `Sources/BrowserdoorCore` unless noted.

| Term | Meaning |
|---|---|
| **Link** | A URL Browserdoor may hand to a browser: `http`, `https` or `file`. Anything else (`javascript:`, `--flags`, …) never becomes a link. |
| **Incoming item** | What macOS hands Browserdoor: a URL, an `.html` file or a `.webloc` file. `LinkOpener.links(from:)` turns items into links. |
| **Target** | One entry the user can pick: a Zen space, a Chromium or Firefox profile, or a browser/app. Has a stable ID (`zen:{uuid}`, `chromium:<bundleId>:<dir>`, `firefox:<bundleId>:<path>`, `app:<bundleId>`). |
| **Zen space** | A Zen workspace, read from `zen-sessions.jsonlz4` and opened with `zen --space`. |
| **Chromium profile** | A profile of Chrome, Brave, Edge, Vivaldi or Chromium, opened with `--profile-directory`. |
| **Firefox profile** | A Firefox profile from `profiles.ini` or a profile group database, opened with `--profile <dir>`. |
| **Profile group** | Firefox's newer profile manager (since 138): profiles stored in `Profile Groups/<StoreID>.sqlite`, with one representative in `profiles.ini`. |
| **Extra app** | An app the user added as a target even though it isn't a known browser. |
| **Discovery** | Finding the targets on this Mac (`Discovery`, behind the `BrowserEnvironment` seam). |
| **Target catalog** | `TargetCatalog`: config + discovery → the targets, their labels, hotkeys and order; saves edits. The single source for the picker and the settings window. |
| **Default target** | The target `Enter` opens (star in the settings). |
| **Hotkey** | The key that picks a target in the picker: custom, or an automatic number key. |
| **Picker** | The floating panel that appears for a link. |
| **Picker session** | `PickerSession`: one appearance of the picker, its links, entries and selection; turns input into effects (close, open, copy). |
| **Link opening** | `LinkOpener`: links + target → launch, including Zen's running/cold handling, behind the `LaunchPort` seam. |
| **Installation** | `Installation`: where Browserdoor lives, the stable link and the login item. |
| **Stable link** | `~/Applications/Browserdoor.app`, a symlink to Homebrew's `opt` path that survives `brew upgrade`. |
| **Login item** | The LaunchAgent that runs `open -a <stable link>` at login. |
| **Update policy** | `UpdatePolicy`: when to check for a new release and what to announce, behind `ReleaseSource` and `UpdatePreferences`. |
| **Put off** | "Later" on an update notice: automatic checks don't announce that release again. |
| **Zen icon cache** | `ZenIconCache`: Zen's space icons extracted from `omni.ja`, once per Zen version. |
