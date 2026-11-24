# Changelog: Browserdoor for Windows

What changes for users of the Windows app, released as `windows-vX.Y.Z` (see [ADR 0001](../docs/adr/0001-windows-port-in-rust-tauri.md)). The macOS app has its own [CHANGELOG.md](../CHANGELOG.md).

## Unreleased

## 0.1.0 – 2026-11-25

The first Windows version of Browserdoor: the same link picker as on macOS.

- Becomes a browser Windows can make the default; the first start offers to open the Windows settings for it and turns on autostart.
- The picker opens at the mouse for every link: Zen spaces (Zen 1.24 or later), every Chrome, Edge, Brave, Vivaldi and Chromium profile, every Firefox profile, and every other installed browser.
- Number keys or your own keys pick a target, Enter opens the default target, Ctrl+C copies the link. Links that arrive at the same time open together with one choice.
- Settings window with General, Targets and Advanced tabs: sort, rename, hide, set keys and the default target, add any program as a target, choose another Zen profile.
- Tray icon with the menu from the macOS menu bar (open a link from the clipboard, check for updates, settings); it shows a dot while Browserdoor isn't the default browser.
- Installs and updates with Scoop. Once a day Browserdoor checks for a new version and offers to update.
- English and German, following the Windows display language.
