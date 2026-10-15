# Sharing directories

Directory Keeper can save your whole directory to a file, and add the contents of someone else's file to your own directory.

## Exporting

1. Open Total RP 3 → **Directory** → **Characters**, and click **Export** (the right-pointing wrench next to the search button), or type `/tdk export`.
2. Confirm. The export runs in the background for a second or two.
3. Click **Reload**, or reload or log out later. The game writes the file at that moment.
4. Send this file, preferably zipped:

   `World of Warcraft\_retail_\WTF\Account\<YOUR ACCOUNT FOLDER>\SavedVariables\TRP3_DirectoryKeeper_Exchange.lua`

   A 15,000-profile directory gives a file of about 48 MB, or about 15 MB zipped.

   The game cannot tell addons where it is installed or what your account folder is called, so the export and import windows show this path with `<YOUR ACCOUNT FOLDER>` as a placeholder. To open your World of Warcraft folder: in the Battle.net app, select World of Warcraft, click the gear icon next to the Play button, then **Show in Explorer**. Most players have exactly one folder inside `WTF\Account`.

An export replaces whatever was in that file before, including a received export you have not imported yet. The confirmation tells you when that is the case.

### What an export contains

- Every character in your directory that is bound to a profile, the profiles those characters use, and their pets and mounts (companion profiles).
- Profile contents as Total RP 3 stores them: characteristics, About, glances, currently/OOC, last-seen date and zone, and read/unread flags.

### What an export never contains

- Your **ignore list**, and any character on it (with their profiles and companions).
- Your **own profiles, notes and relations.** Those live in `totalRP3.lua`, not in the directory. If other players have met your characters, your profiles as *they* received them can be in their directory, like anyone else's.
- Profiles no character points to. TRP3 keeps these after a player switches profiles, but never lists them.

## Importing

1. **Close the game**, or go to the character selection screen.
2. Put the received `TRP3_DirectoryKeeper_Exchange.lua` (unzipped) into your own `World of Warcraft\_retail_\WTF\Account\<YOUR ACCOUNT FOLDER>\SavedVariables\` folder, replacing the file of the same name if there is one.
3. Log in, open the Directory and click **Import** (the left-pointing wrench), or type `/tdk import`.
4. Directory Keeper first asks whether you have placed the file, and shows again where it goes. Click **Import**.
5. Directory Keeper reads the file in the background and shows what it would add and skip. Nothing has changed yet.
6. Click **Reload**. The entries are added and the game reloads. **Cancel** imports nothing.

Don't place the file while you're logged in on a character that has already exported or imported this session. The game would overwrite it at logout.

### What an import does

An import only **adds**:

| Received | Result |
|---|---|
| A character you don't have | Added, with its profile |
| A character you don't have, whose profile you already have (for example someone's alt) | Added and linked to **your** copy of the profile |
| A character you already have | Skipped. Your entry is never changed, even if theirs is newer. Total RP 3 fetches the current profile when you meet that player. |
| A character on your ignore list | Skipped |
| A pet or mount profile you don't have | Added, linked only to owners in your directory |

Imported entries go into your archive, not into Total RP 3's own file. An import therefore never brings TRP3's own file closer to the limit.

Last-seen dates are capped at the export date, so a wrong clock on the exporter's PC cannot make imported profiles look newer than they are.

## How received files are checked

A received file comes from another player, so it is treated as untrusted:

- **Never run as code.** The directory inside the file is stored as text blocks. Directory Keeper reads them with its own small parser, which accepts only plain data: text, numbers, true/false and nested lists. Anything else, such as function calls or extra code, makes the import stop with "This export could not be read".
- **Checked field by field.** Only the fields Total RP 3 uses are kept, with the expected types. Character names containing control characters or UI escape codes are rejected, and texts are limited to 256 KB. Oversized or deeply nested entries are rejected.
- **Cleaned by Total RP 3.** New profiles go through Total RP 3's own sanitizers, the same ones it uses for profiles received in game.
- **Version check.** The export records Total RP 3's data format. An import from a different Total RP 3 data format is refused, so both players need the same Total RP 3 version.

One limit to be aware of: the game itself loads every saved-variables file as Lua when it starts. That is true of all addon files, and Directory Keeper cannot change it. Only accept exchange files from people you trust, as you would with an addon.

## Good to know

- **Reporting profiles:** an imported profile shows the exporter's last-seen date in Total RP 3's Report window. Blizzard support checks reports against the profiles *your* game received, so only report profiles you have seen in game yourself.
- **Privacy:** the directory holds profiles players broadcast to everyone around them, but also when and where each was last seen (zone). Share directories with people you trust.
