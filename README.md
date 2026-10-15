# TRP3 Directory Keeper

A companion addon for [Total RP 3](https://github.com/Total-RP/Total-RP-3) that keeps **every --SOUL--, khem, roleplayer profile you have ever met** and lets you **share whole directories** with other players, for example if their profile was wiped.

Total RP 3 stores everyone you meet in its *Directory*. Normally it clears every 30 days and you loose all the profiles, you do not see their names when scanning the map etc. TRP3 keeps that directory in one saved-variables file. If purges are turned off, that file stops loading at roughly 16,000 profiles, because of a hard limit in the game's Lua engine. The game then shows an empty directory and logs `constant table overflow`. Directory Keeper keeps a separate, high-capacity archive next to TRP3's own data, so the directory can keep growing without hitting that limit, while TRP3 does its own regular purges.

> Directory Keeper is an unofficial addon. It is not made or supported by the Total RP 3 team. Please do not report Directory Keeper problems to them.

## Features

- **Nearly unlimited directory.** Everyone you have ever met is kept in one archive file, stored compactly enough that it never reaches the game's limit. At login they all appear in TRP3's Directory, whatever TRP3's purge setting is.
- **Always up to date.** At every logout, the archive takes the latest version of everyone you met that session.
- **Relations and notes are safe.** Profiles you have relations or notes on always stay in TRP3's own file, as with TRP3's own purge.
- **Export and import.** Two buttons in the Directory let you save your directory to a file and add someone else's. Imports only add player profiles you have not met yet; your existing entries are never changed.
- **No settings changed.** Directory Keeper never changes TRP3's settings, including its purge setting.
- **TRP3's own file stays untouched in format.** Total RP 3 saves exactly what it would save without this addon. If you ever remove Directory Keeper, Total RP 3 keeps working normally with its own data.

## Requirements

- World of Warcraft Retail, patch 12.1.5 (Interface 120105)
- Total RP 3 3.5.1

## Installation

1. Download `TRP3_DirectoryKeeper-<version>.zip` from the [Releases](https://github.com/Dove2137/TRP3_DirectoryKeeper/releases) page (not the green "Code" button, which downloads the source with tests and docs). Extract it into `World of Warcraft\_retail_\Interface\AddOns\`, so you get these three folders:
   - `TRP3_DirectoryKeeper`
   - `TRP3_DirectoryKeeper_Archive`
   - `TRP3_DirectoryKeeper_Exchange`
2. Restart the game. New addon folders are only detected at startup.
3. In the AddOns list on the character selection screen, choose **All characters** at the top, and make sure all Directory Keeper entries are enabled. They appear grouped under *TRP3 Directory Keeper*.

## Usage

Play as usual. Open the Directory (Total RP 3 → Directory → Characters) to see everyone in the archive.

| Command | What it does |
|---|---|
| `/tdk` | Status: what TRP3 shows, archive size, TRP3's own file usage, timings |
| `/tdk export` | Same as the Export button |
| `/tdk import` | Same as the Import button |

### Sharing a directory

The **Import** (left wrench) and **Export** (right wrench) buttons are next to the search button at the bottom of the Directory's Characters tab.
Importing: with the game closed (or at character selection), put the received file in the same directory as the export: Warcraft\_retail_\WTF\Account\<YOUR ACCOUNT FOLDER>\SavedVariables\TRP3_DirectoryKeeper_Exchange.lua - Log in, open the characters tab and click Import. The game reloads after the import.
Exporting: click Export, confirm, then reload. The file is stored at: Warcraft\_retail_\WTF\Account\<YOUR ACCOUNT FOLDER>\SavedVariables\TRP3_DirectoryKeeper_Exchange.lua - The game shows this path, and how to find your World of Warcraft folder, after each export/import.

Both players need the same Total RP 3 version. See [docs/SHARING.md](docs/SHARING.md) for what is included, what is skipped, and how received files are checked.

## Things to know

- **Uninstalling** is safe. Total RP 3 keeps its own directory. The archive file (`TRP3_DirectoryKeeper_Archive.lua` in `SavedVariables`) stays on disk until you delete it, and also works as a backup of everyone you have met.
- **Deleting a profile on a character without Directory Keeper:** it comes back from the archive the next time you play a character with it.
- **Imported profiles and TRP3's Report button:** an imported profile shows the *exporter's* last-seen date, and Blizzard cannot verify a report about a profile you never received yourself. Report only what you have seen in game.
- **Companion details:** pets and mounts from the archive may miss some tooltip details until you meet their owner again.
- **After a Total RP 3 update that changes its data format,** Directory Keeper pauses and leaves the archive untouched until it is updated too. `/tdk` shows why.

## How it works

At login, after Total RP 3 has loaded and run its own cleanup, the archive is added to TRP3's directory in memory. At logout, the archive is updated from TRP3's directory, and the entries that were only added for display are taken back out before the game saves TRP3's file. Details, measurements and failure handling are in [docs/HOW_IT_WORKS.md](docs/HOW_IT_WORKS.md).

## Development

Repository layout, local setup and the test suite, which runs the addon on real saved-variables files under plain Lua 5.1: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## License

Licensed under the [Apache License 2.0](LICENSE), the same licence as Total RP 3.

## Credits

- **Total RP 3** by the Total RP 3 Authors: created by Telkostrasz and Ellypse, developed by Solanya (project lead), Meorawr, Sælorable and Raenore. See their [authors list](https://github.com/Total-RP/Total-RP-3/blob/main/AUTHORS.md).
- **Directory Keeper** by Claude (and roughly 6 hours of my QA Engineer patience - Kanedaw)
