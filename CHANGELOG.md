# Changelog

What changed for people using Browserdoor. Each release on GitHub starts with its section from this file.

## Unreleased

- The picker shows a link's host in bold and the rest in gray. Hosts with non-ASCII letters appear in Punycode, so a look-alike such as `аpple.com` with a Cyrillic а doesn't pass for the real one. A file shows its name and folder.
- The selected row in the picker looks like a selected menu item, and the default target carries a `↩` mark.
- Profiles of the same browser get a small lettered circle on the icon, so two Chrome profiles no longer look alike.
- Tab, ⇧Tab, Home and End move the selection in the picker; ⌘, opens the settings. A picker with every target hidden says so and offers the settings.
- A mouse resting on the picker when it opens no longer changes the preselected target; hover selects once the mouse moves.
- VoiceOver reads the picker's rows as buttons, with their key and which one is selected.
- The menu bar menu has "About Browserdoor" and "Open Link from Clipboard…"; with ⌥ it offers "Report an Issue…" and "Show Configuration in Finder". The version line and the second update item are gone.
- The menu bar icon carries a dot while Browserdoor isn't your default browser.
- The menu bar icon can be hidden in the settings or by ⌘-dragging it away; opening Browserdoor again shows the settings.
- ⌘M and ⌘H work in the settings window.
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
