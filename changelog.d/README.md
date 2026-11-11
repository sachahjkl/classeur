# changelog.d

One file per change a person sees, never an edit of `CHANGELOG.md`. `classeurtool ship` assembles them into the version's
section and deletes them; `classeurtool check` refuses a malformed one.

    odin run tools/classeurtool -collection:gt=ext/gui_toolkit/src -out:build/classeurtool -- changelog new Fixed tab-ghost "**The tab's ghost fits its row**: ..."

A fragment is `<yyyyMMdd-HHmmss>-<subject>.md`: `type: <Added|Changed|Deprecated|Removed|Fixed|Security>`, a blank line,
then the one entry, a short bold summary first (the format: gui_toolkit's docs/changelog.md).
