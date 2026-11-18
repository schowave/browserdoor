# Browserdoor

- **Spec**: `SPEC.md` is authoritative for discovery, target IDs and launch commands. A behaviour change updates it in the same commit.
- **Terms**: `GLOSSARY.md` names the concepts used in code and reviews.
- **Setup**: `mise run setup` on a fresh clone (pinned tools, Swift packages).
- **Check**: `mise run check` before every commit; it is what GitHub CI runs.
- **Release**: review the changes since the last tag (`/code-review high <last tag>`), turn "Unreleased" in `CHANGELOG.md` into the version's section, push main, then `mise run release vX.Y.Z`. A change users notice gets a CHANGELOG line when it lands.
- **Real-machine check**: `mise run targets` prints the targets the app finds on this Mac and the command each would open a link with. Reach for it to verify discovery or launching; it launches nothing.
