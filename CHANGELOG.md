# Changelog

What changed for people using Browserdoor. Each release on GitHub starts with its section from this file.

## Unreleased

- A key you give a target in the settings now moves to that target; before, two targets could show the same key while the picker gave it to only one.
- Zen space icons that are still being extracted appear in an open picker or settings window as soon as they're ready, not only the next time.
- The picker stays on screen when more links arrive while it's open.

## v0.5.1 – 2026-11-12

- The bundle ID moved from `io.github.schowave.doorman` to `io.github.schowave.browserdoor`. The first start after updating from 0.4.x or earlier carries your settings, login item and menu bar position over. macOS ties the default browser to the bundle ID, so it asks you once to confirm Browserdoor again.
- Updating from the menu only restarts the Browserdoor that asked, not a development build running next to it.

## v0.4.0 – 2026-11-12

- Firefox profiles show up as separate targets, including the ones from Firefox's new profile manager.
- `Browserdoor.app/Contents/MacOS/Browserdoor --list-targets` prints every target and the command it opens a link with, for bug reports.

## v0.3.0 – 2026-11-10

- Doorman is now Browserdoor. See the README for the one-time `brew trust` before upgrading; settings and the `doorman` command carry over.

## v0.2.6 – 2026-11-09

- The update check uses GitHub's `releases/latest` redirect instead of the rate-limited API.

## v0.2.5 – 2026-11-09

- Homebrew installs a prebuilt bottle on macOS 15 or later, so Xcode is no longer needed there.

## v0.2.3 – 2026-11-08

- After an update, the old version's LaunchServices entry is removed, so "Open with" no longer lists it twice.

## v0.2.2 – 2026-11-08

- Links no longer get lost when Zen is running but was taken for closed.

## v0.2.0 – 2026-11-08

- Settings window: reorder, hide, rename targets, give them keys, add apps. Update check. English and German.

## v0.1.0 – 2026-11-08

- First release: a link picker for Zen workspaces, Chromium profiles and browsers.
