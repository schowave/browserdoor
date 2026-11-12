# Browserdoor

- **Spec**: `SPEC.md` (German) is authoritative for discovery, target IDs and launch commands. A behaviour change updates it in the same commit.
- **Terms**: `GLOSSARY.md` names the concepts used in code and reviews.
- **Check**: `mise run ci` before every commit; it is what GitHub CI runs.
- **Real-machine check**: `mise run targets` prints the targets the app finds on this Mac and the command each would open a link with. Reach for it to verify discovery or launching; it launches nothing.
