# How Directory Keeper works

This page explains the problem Directory Keeper solves and exactly what it does at login and logout. It also covers how it behaves when something goes wrong.

## The problem: one file, one limit

Total RP 3 stores the directory in the saved variable `TRP3_Register`. That variable lives in its own addon, `totalRP3_Data`, so it gets its own file: `WTF\Account\<account>\SavedVariables\totalRP3_Data.lua`.

The game loads a saved-variables file by compiling it as **one Lua 5.1 function**. Lua 5.1 allows at most **262,143 unique constants** (2^18 − 1) per function. Every distinct string and number in the file counts once: profile IDs, character names, every description, most timestamps. If a file needs more, the game refuses to load it with `constant table overflow`. TRP3 then starts with an empty directory.

Measured on a real directory: about **16.5 constants per profile**. A directory of 15,510 profiles needed 255,052 constants (97.3% of the limit), so the limit is reached at about **16,000 profiles**. File size in bytes does not matter, only the number of distinct values.

TRP3's purge normally keeps the directory below that. With purge off, the directory grows until the file no longer loads.

## The solution: an archive stored as text blocks

Directory Keeper keeps its archive in its own file, from the data-only addon `TRP3_DirectoryKeeper_Archive`. Storing the archive there as plain tables would hit the same limit, so it is stored as **text blocks**:

- Each section (profiles, characters, companions) is split into numbered blocks. A block is one string of the form `return{...}` holding about 64 profiles (or 256 characters).
- A string counts as **one** constant however much it contains. A real 15,500-profile archive (53 MB) needs only **625 constants**, so the file can grow far beyond any realistic directory.
- An entry always goes into the same block, chosen by a hash of its key. Blocks therefore stay stable from one save to the next.

| Addon | Saved variable | Contents |
|---|---|---|
| `totalRP3_Data` (Total RP 3) | `TRP3_Register` | TRP3's own directory, in TRP3's normal format |
| `TRP3_DirectoryKeeper` | `TRP3DK_State` | Status and timings of the last logout |
| `TRP3_DirectoryKeeper_Archive` | `TRP3DK_Archive` | The archive: text blocks per section, plus the TRP3 data format, save date and counts |
| `TRP3_DirectoryKeeper_Exchange` (load on demand) | `TRP3DK_Exchange` | An export, or a received export to import |

The ignore list (`TRP3_Register.blockList`) is never archived.

### Writing only what changed

Rewriting every block at every logout would take over a second for a large archive. So Directory Keeper notes a small *fingerprint* of every entry at login: the last-seen date, version numbers, link count and read flag of profiles; the profile, guild and client of characters; the version numbers and links of companions. At logout only the blocks holding new, deleted or changed entries are written again. All other blocks are saved exactly as they were read. A typical session rewrites a handful of blocks; a session without changes rewrites none.

Every 20 logouts, and whenever the number of blocks no longer suits the archive's size, all blocks are rewritten. That also picks up rare changes no fingerprint covers.

## Login

1. **`ADDON_LOADED`.** The archive's text blocks are read back into tables, and every entry's fingerprint is noted. At the very first login the archive is empty; it is filled from TRP3's directory at the first logout.
2. **`PLAYER_LOGIN`.** Total RP 3 starts. It runs its data migrations, reads its directory and runs its login cleanup: it removes relations to unknown profiles, purges by age if purge is on, and unlinks orphaned characters and companions.
3. **`PLAYER_ENTERING_WORLD`.** Directory Keeper adds the archive to TRP3's directory **in memory**:
   - **Profiles:** archive profiles TRP3 doesn't have are added. When both have a profile, the one with the newer last-seen date (`profile.time`) is used. Profiles without data are skipped (TRP3 deletes those itself).
   - **Characters:** missing characters are added; ignored characters never are. When both have a character bound to different profiles, the binding whose profile was seen last wins.
   - **Companions:** missing companion profiles are added.
   - Profile `link` tables and character `profileID`s are kept in step, the way TRP3 keeps them.
   - Everything added is recorded for logout. TRP3's directory now shows everyone.
   - The Import and Export buttons are created, and the near-limit warning is printed if TRP3's own file is above 90% of the estimated limit.

Directory Keeper adds the archive *after* TRP3's own cleanup. That way TRP3's purge only decides what TRP3 keeps in its own file; it never hides anyone from the directory screen.

## Logout

`PLAYER_LOGOUT` is registered late, so Total RP 3's own logout handlers run first. Then:

1. **Update the archive** from TRP3's directory:
   - Entries deleted in TRP3 during the session are removed from the archive. This covers deletions by you and by TRP3 itself, for example when a character switches profile.
   - Profiles: the newer last-seen date wins. In practice that is TRP3's copy, often the very same table as the archive's.
   - Characters: TRP3's binding is taken unless the archive's points to a profile seen more recently.
   - Companions: TRP3's current version is taken.
2. **Hand TRP3 back its own directory.** Entries that were only added for display are removed from `TRP3_Register` again. A profile stays in TRP3's file if any of these is true:
   - it was TRP3's own at login;
   - it was seen this session (`time` ≥ session start), unless it was imported;
   - one of TRP3's own characters points to it;
   - you have a relation or a note on it (`TRP3_Profiles[*].relation`, `TRP3_Profiles[*].notes`, `TRP3_Notes`).

   A profile's characters stay or go with it. An added companion stays while one of its owners stays.
3. **Write the archive file:** only the changed blocks, together with the TRP3 data format, the date and the counts.

The game then writes all files. TRP3's file contains exactly what TRP3 would have saved without Directory Keeper.

### Why relations need protecting

At every login, TRP3 deletes relations that point to profiles missing from its directory, and it does that *before* Directory Keeper adds the archive. If a profile you have a relation with were only in the archive, the relation would be lost at the next login. TRP3's own purge protects the same profiles for the same reason.

## Failure handling

| Situation | What happens |
|---|---|
| The archive addon is disabled | The game does not load Directory Keeper at all (the archive is a required dependency). TRP3 runs normally, and the archive file is left untouched. |
| Only the code addon is disabled | The archive addon still loads and the game saves its file back unchanged. |
| Total RP 3 updated its data format (`TRP3_Flyway.currentBuild` differs from the archive's) | Directory Keeper pauses: nothing is added, and the archive is not rewritten. `/tdk` shows the reason. |
| The archive file was written by a newer Directory Keeper | Directory Keeper pauses and leaves the file alone. |
| An archive block can't be read | It is reported in chat and kept in the file untouched, never thrown away. |
| Adding the archive fails at login | The error is shown. At logout everything that was added is still taken back out of TRP3's file, and the archive file is not rewritten. |
| Updating or writing the archive fails at logout | The archive file is left as loaded, so the previous archive is saved unchanged. TRP3's file is still trimmed. |
| TRP3's own file overflows (purge off, too many profiles met) | The game can't load it, so TRP3 starts empty. The archive still has everyone and still shows them. |
| Crash or Alt+F4 | The game saves nothing. All files keep their previous, consistent state. |

## Performance

Measured by the test suite on a real 15,498-profile directory under Lua 5.1:

| Step | Time |
|---|---|
| Reading the archive's text blocks (`ADDON_LOADED`, during the loading screen) | 0.5–0.7 s |
| Adding the archive to TRP3's directory | 30–45 ms |
| Logout: update, trim, write changed blocks | ~0.13 s |
| Logout with a full rewrite (first logout, then every 20 logouts) | 1.1–1.4 s |
| Export of the whole directory (background, over ~65 frames) | ~1.1 s |
| Reading an import (background, over ~70 frames) | ~1.2 s |

The game's own reading and writing of the files is not included. The archive file is about as large as TRP3's own file would be with everyone in it. With TRP3's purge off, both files hold nearly everyone, so the game reads and writes about twice as much as without Directory Keeper. While playing, Directory Keeper does no work at all.

`/tdk` shows the times measured in your game.
