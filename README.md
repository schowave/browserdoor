# Doorman

Doorman is a link picker for macOS, in the spirit of Browserosaurus. Set it as your default browser. When you click a link, it asks where the link should go:

- a **Zen workspace**, opened with Zen's `--space` flag (Zen ≥ 1.24)
- a **Chrome/Brave/Edge/Vivaldi profile**
- any other installed browser

## Install

```sh
brew install schowave/tap/doorman
open "$(brew --prefix)/opt/doorman/Doorman.app"
```

On first start, Doorman offers to become the default browser and adds a login item. It also links itself to `~/Applications/Doorman.app`, which keeps pointing at the current version after `brew upgrade`. After an upgrade, restart Doorman with `open ~/Applications/Doorman.app`. The formula builds from source, so you need the Xcode Command Line Tools with Swift 6, on macOS 14 or newer.

## Use

| Key | Action |
|---|---|
| `1`–`9`, `0` or the configured key | open in that target |
| `↑` `↓` and `Enter` | choose, then open |
| `⌘C` | copy the URL |
| `Esc`, or a click outside | cancel |

When several links arrive at once, they collect in one panel and all open in the target you pick.

## Configure

`~/.config/doorman/config.json` is optional. Use *menu bar → Konfiguration öffnen…* to create it with every target that Doorman currently detects.

```json
{
  "defaultTarget": "zen:{b4ac0402-9e47-4873-89b6-5dfeffe77a7e}",
  "order": ["zen:{b4ac0402-9e47-4873-89b6-5dfeffe77a7e}", "app:com.apple.Safari"],
  "hidden": ["app:com.google.Chrome.beta"],
  "extraApps": ["com.googlecode.iterm2"],
  "targets": {
    "zen:{b4ac0402-9e47-4873-89b6-5dfeffe77a7e}": { "label": "Privat", "hotkey": "p" }
  },
  "zen": { "profilePath": null }
}
```

Target IDs look like this:

| ID | Target |
|---|---|
| `zen:{uuid}` | a Zen workspace |
| `chromium:<bundleId>:<profileDir>` | a Chromium profile |
| `app:<bundleId>` | any other browser |

## Develop

Tooling and tasks come from [mise](https://mise.jdx.dev). Swift comes from Xcode or the Command Line Tools.

```sh
mise install        # actionlint, shellcheck, swiftformat (versions pinned in mise.toml)
mise tasks          # list all tasks
mise run test       # unit tests
mise run app        # build/Doorman.app (ad-hoc signed)
mise run run        # build and start
mise run format     # swiftformat
mise run ci         # everything CI runs: lint, test, app, formula check
```

The tasks in `.mise/tasks/` are plain shell scripts. The Homebrew formula runs `.mise/tasks/install` directly, so mise isn't needed to install Doorman.

## Releases and dependencies

- **Manual release:** push a tag such as `v0.2.0`. The release workflow then tests and builds Doorman, creates the GitHub release and updates `Formula/doorman.rb` in [schowave/homebrew-tap](https://github.com/schowave/homebrew-tap).
- **Renovate** (GitHub App, `renovate.json`): bundles all updates (GitHub Actions, mise tools) into one PR on Monday mornings and merges it once CI is green. Each such merge produces a **patch release** through `auto-release.yml`.

The design is described in [SPEC.md](SPEC.md).

## License

MIT
