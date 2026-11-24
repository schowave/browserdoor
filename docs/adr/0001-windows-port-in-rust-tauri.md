# Windows version is a Rust/Tauri rebuild in this repo, not a Swift port

Browserdoor comes to Windows as the same product: one `SPEC.md` with per-platform sections, one `GLOSSARY.md`, shared test fixtures. The Windows app is rebuilt in Rust with Tauri under `windows/`, rather than porting `BrowserdoorCore` to Swift on Windows, because Swift has no mature Windows UI layer (WinUI bindings are immature) and Tauri also carries over to Linux later. The roughly 3,000 lines of core logic are re-derived from the spec and fixtures, not shared as code.

## Consequences

- Two implementations of the same domain: the glossary is the contract between them, and module names in `windows/` follow it.
- Windows releases are tagged `windows-v*` and versioned independently; the macOS release workflows only match `v*` and ignore them.
- Configuration is per computer (target IDs embed a platform **App ID**), so the two apps never need a shared config format beyond the same keys.
- Windows was built without first checking demand, because the author wants it.

## Considered Options

- **Swift on Windows with WinUI bindings**: keeps one core, but the UI layer is the risky part and would be on immature tooling.
- **.NET (WinUI/WPF)**: good Windows UI, but no path to Linux and a third language.
- **Separate repo `browserdoor-windows`**: simpler release pipeline, but spec, glossary and fixtures would drift.
