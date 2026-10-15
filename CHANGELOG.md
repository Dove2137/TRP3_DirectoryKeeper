# Changelog

## 1.0.0 (2026-10-15)

First release.

- **Archive.** Every directory entry ever seen is kept in one file, from the data-only addon `TRP3_DirectoryKeeper_Archive`. It is stored as text blocks, so it never reaches the game's saved-variables limit, and at logout only the blocks that changed are rewritten. At login the archive is shown in TRP3's Directory. At logout it is updated with everyone met that session, and deletions made in TRP3 are applied to it.
- **Clear export and import instructions** in game, showing where the exchange file is and how to open the World of Warcraft folder.
- **TRP3's own file stays standard.** It keeps exactly what Total RP 3 would save without this addon, and no Total RP 3 setting is changed. Profiles you have relations or notes on always stay in it.
- **Export and import** of whole directories through an exchange file (`TRP3_DirectoryKeeper_Exchange`):
  - **Import** and **Export** buttons in the Directory's Characters tab, and `/tdk import` / `/tdk export`.
  - Imports only add new characters and never change existing ones. Ignored characters are skipped, and the ignore list is never exported.
  - Received files are read by a data-only parser, checked field by field, and passed through Total RP 3's sanitizers.
- A chat warning when TRP3's own file is near the saved-variables limit.
- A pause mode: if TRP3's data format changed or TRP3 did not load, the archive is left untouched.
- `/tdk` status: what TRP3 shows, archive size, TRP3's own file usage, timings.
- Test suite running the addon on real saved-variables files under Lua 5.1.
