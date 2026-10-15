# Development

## Repository layout

```
TRP3_DirectoryKeeper/             the addon (all code)
  Init.lua                        constants, chat output, small helpers
  Serializer.lua                  directory entries <-> text blocks; data-only parser for received files
  Storage.lua                     the archive file: text blocks, fingerprints, writing only changed blocks
  Archive.lua                     login merge, logout update and trim (pure functions)
  Exchange.lua                    export, import planning and applying, background jobs
  UI.lua                          Import/Export buttons, popups
  Main.lua                        events, pause checks, near-limit warning, /tdk
TRP3_DirectoryKeeper_Archive/     data-only addon holding the archive file (TOC only)
TRP3_DirectoryKeeper_Exchange/    load-on-demand data-only addon, the exchange file (TOC only)
tests/                            test harness, unit tests, session simulation
tools/link-addons.ps1             links the addon folders into the game's AddOns folder
tools/package.ps1                 builds the installable zip of a tagged version into dist/
docs/                             documentation
```

`Archive.lua`, `Storage.lua` and most of `Exchange.lua` take the directories as arguments instead of reading globals, so the tests can run them outside the game.

## Local setup

The game loads the addon straight from the repository through directory junctions:

```powershell
powershell -ExecutionPolicy Bypass -File tools\link-addons.ps1
```

Restart the game after adding new addon folders. After code changes, `/reload` is enough. TOC changes need a restart.

## Tests

The tests run the addon under plain **Lua 5.1**, the Lua version the game uses, with small stand-ins for the WoW API (`tests/harness.lua`). Any Lua 5.1 interpreter works. On Windows, the LuaBinaries 5.1.5 build (`lua5.1.exe`) needs no installation.

Run from the repository root:

```sh
lua5.1 tests/test_unit.lua
```

Unit tests on small hand-made directories:
- serializer round-trips, including tricky text;
- the parser refusing code and damaged data;
- merge, update and trim rules, including relation protection and deletions;
- import planning: add-only, ignore list, ID checks, date capping.

```sh
lua5.1 tests/simulate.lua <totalRP3_Data.lua> <totalRP3.lua> <work folder>
```

The session simulation copies a real pair of Total RP 3 saved-variables files into `<work folder>` and plays several logins:
- the first login with Directory Keeper, when the archive is still empty;
- TRP3's purge off, then at 30 days;
- an export;
- an import into a second, small directory.

`tests/trp3_sim.lua` reproduces Total RP 3's own login cleanup. After every session, the files are written the way the game writes them and read back with Lua's own loader, so a file over the constant limit fails there just as in game.

**Always run the simulation on copies.** Never point it at your live `WTF` folder.

## Release checklist

1. Update `## Version` in all three TOC files, and `## Interface` for a new game patch.
2. If Total RP 3 changed its data format (`SCHEMA_VERSION` in `totalRP3/Core/Flyway.lua`), check that the archive's contents still match. Directory Keeper pauses on a format change until it is updated.
3. Check that Total RP 3 still has `TRP3_RegisterListCharactFilter`, `TRP3_RegisterListCharactFilterButton`, the `TRP3_IconButton` template, `TRP3_API.register.sanitizeProfile` and `TRP3_API.ui.tooltip.setTooltipForSameFrame`.
4. Run both test scripts.
5. Add a `CHANGELOG.md` entry.
6. Tag the release (`v<version>`) and build the zip with `powershell -ExecutionPolicy Bypass -File tools\package.ps1 -Version <version>`. It packs the three addon folders from the tag, with the licence, into `dist\`.
7. Create the GitHub release for the tag and attach the zip.
