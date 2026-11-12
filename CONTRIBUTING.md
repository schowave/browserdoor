# Contributing

Bug reports and pull requests are welcome. For a bigger change, open an issue first so we can agree on the approach.

## Setup

You need macOS 14 or later, Xcode 16 and [mise](https://mise.jdx.dev).

```sh
mise install     # actionlint, shellcheck, swiftformat
mise run run     # build build/Browserdoor.app and start it
```

Development builds run as `io.github.schowave.browserdoor.dev` ("Browserdoor Dev"), so they never touch your installed Browserdoor, its settings or the default browser.

## Before a pull request

- `mise run ci` passes. It is what GitHub CI runs: lint, unit tests, docs check, app bundle, formula check.
- New behaviour has a test in `Tests/BrowserdoorCoreTests`. The logic lives in `Sources/BrowserdoorCore` so it can be tested without the UI.
- A change in discovery, target IDs or launch commands updates [SPEC.md](SPEC.md) in the same commit.
- A change users notice gets a line under "Unreleased" in [CHANGELOG.md](CHANGELOG.md).
- `mise run format` fixes formatting.

[GLOSSARY.md](GLOSSARY.md) explains the terms used in the code, and `mise run targets` shows what Browserdoor finds on your Mac.
