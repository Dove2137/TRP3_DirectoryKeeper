-- Unit tests on small hand-made directories.
-- Run from the repository root:  lua5.1 tests/test_unit.lua

package.path = "./tests/?.lua;" .. package.path
local H = require("harness")
H.quiet = true

local env = H.NewEnvironment()
local ns = H.LoadAddon(env, "TRP3_DirectoryKeeper")
local Serializer, Archive, Exchange = ns.Serializer, ns.Archive, ns.Exchange
local Check = H.Check

local function DeepEqual(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then
		if a ~= a and b ~= b then return true end -- NaN
		return a == b
	end
	for k, v in pairs(a) do if not DeepEqual(v, b[k]) then return false end end
	for k in pairs(b) do if a[k] == nil then return false end end
	return true
end

---------------------------------------------------------------------------
print("Serializer")
---------------------------------------------------------------------------

local tricky = {
	plain = "Faelix Fortuna",
	quotes = 'He said "hi" and \'bye\'',
	backslashes = "C:\\path\\to\\file\\",
	newlines = "line one\nline two\r\nline three",
	zero = "a\0b\0" .. "1",
	escapes = "\\1 \\n literally, then \1\2\3 control bytes and \255",
	colors = "|cffff0000red|r and |TInterface\\Icons\\x:16|t",
	unicode = "Æthelward Varthäs Kañe 角色扮演",
	digitsAfterEscape = "\r12\n34\"56",
	numbers = { 0, -1, 1766173303, 0.1, -2.5e-10, 1e300, 2^53 + 1 },
	special = { inf = 1 / 0, ninf = -1 / 0 },
	booleans = { yes = true, no = false },
	nested = { a = { b = { c = { d = "deep" } } } },
	[1] = "array part", [2] = "two", [10] = "sparse",
	[true] = "boolean key",
	[-5.5] = "float key",
}

local chunker = Serializer.NewChunker()
chunker:Add("profile1", tricky)
chunker:Add("profile2", { characteristics = { FN = "Second" } })
local chunks = chunker:Finish()
Check(#chunks == 1, "small data fits one chunk")
local parsed = Serializer.Parse(chunks[1])
Check(DeepEqual(parsed.profile1, tricky), "round trip keeps every value exactly")
Check(parsed.profile2.characteristics.FN == "Second", "second entry read back")

local nan = Serializer.Parse(select(1, (function()
	local c = Serializer.NewChunker(); c:Add("x", { v = 0 / 0 }); return c:Finish()[1]
end)()))
Check(nan.x.v ~= nan.x.v, "NaN round trip")

-- chunks split at CHUNK_BYTES
local big = Serializer.NewChunker()
for i = 1, 3000 do big:Add("id" .. i, { text = string.rep("x", 200), n = i }) end
local bigChunks = big:Finish()
Check(#bigChunks >= 2, "large data is split into several chunks (" .. #bigChunks .. ")")
local total = 0
for _, chunk in ipairs(bigChunks) do for _ in pairs(Serializer.Parse(chunk)) do total = total + 1 end end
Check(total == 3000, "every entry is in exactly one chunk")

-- the parser refuses anything that is not plain data
local function Rejects(text, label)
	local ok = pcall(Serializer.Parse, text)
	Check(not ok, "parser rejects " .. label)
end
Rejects('return{["a"]=os.exit(),}', "function calls")
Rejects('return{["a"]=("x"):rep(1e9),}', "method calls")
Rejects('return{["a"]=1,} while true do end', "trailing code")
Rejects('return{["a"]="unterminated,}', "unterminated text")
Rejects('return{["a"]={{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{{1}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}},}', "excessive nesting")
Rejects('local x = 1 return{}', "other code before the data")
Rejects('return{["a"]="\\q",}', "unknown escapes")
Rejects(42, "non-text values")

---------------------------------------------------------------------------
print("Archive merge, update and trim")
---------------------------------------------------------------------------

local NOW = 2000000000
local OLD = NOW - 400 * 86400

local function Profile(name, seen, ...)
	local link = {}
	for _, characterID in ipairs({ ... }) do link[characterID] = 1 end
	return { characteristics = { FN = name }, time = seen, link = link }
end

-- TRP3's own directory after its own login purge: two recent profiles.
local trp3 = {
	profiles = {
		P_OWN = Profile("Own", NOW - 3600, "Own-Realm"),
		P_BOTH = Profile("Both, TRP3 newer", NOW - 60, "Both-Realm"),
	},
	character = {
		["Own-Realm"] = { profileID = "P_OWN" },
		["Both-Realm"] = { profileID = "P_BOTH" },
		["Ignored-Realm"] = {}, -- TRP3 keeps ignored characters without a profile
	},
	companion = {},
	blockList = { ["Ignored-Realm"] = "spam" },
}
-- The archive: everything ever seen.
local archive = {
	profiles = {
		P_OWN = trp3.profiles.P_OWN,
		P_BOTH = Profile("Both, archive older", OLD, "Both-Realm"),
		P_OLD = Profile("Old friend", OLD, "Old-Realm"),
		P_REL = Profile("Has a relation", OLD, "Rel-Realm"),
		P_IGN = Profile("Ignored", OLD, "Ignored-Realm"),
		P_EMPTY = { characteristics = {}, time = OLD, link = {} },
		P_SEEN = Profile("Met again today", OLD, "Seen-Realm"),
	},
	character = {
		["Own-Realm"] = trp3.character["Own-Realm"],
		["Both-Realm"] = { profileID = "P_BOTH" },
		["Old-Realm"] = { profileID = "P_OLD" },
		["Rel-Realm"] = { profileID = "P_REL" },
		["Ignored-Realm"] = { profileID = "P_IGN" },
		["Seen-Realm"] = { profileID = "P_SEEN" },
	},
	companion = {
		C_OLD = { data = { NA = "Pet" }, PE = {}, links = { ["Old-Realm_Pet"] = 1 } },
	},
}

local session = Archive.Merge(trp3, archive, trp3.blockList, NOW, {})
Check(trp3.profiles.P_OLD ~= nil and trp3.character["Old-Realm"] ~= nil, "archive-only profile and character are shown")
Check(trp3.profiles.P_BOTH.characteristics.FN == "Both, TRP3 newer", "TRP3's newer copy wins over an older archive copy")
Check(trp3.profiles.P_EMPTY == nil, "profiles without data are not added (TRP3 purges those)")
Check(trp3.character["Ignored-Realm"].profileID == nil, "ignored characters are not added from the archive")
Check(trp3.companion.C_OLD ~= nil, "archive companions are shown")
Check(trp3.profiles.P_OLD.link["Old-Realm"] == 1, "links are consistent after merging")
Check(session.ownProfiles == 2, "TRP3's own profile count is recorded")

-- During the session: meet someone new, meet an archived character again, delete a profile.
trp3.profiles.P_NEW = Profile("New today", NOW + 10, "New-Realm")
trp3.character["New-Realm"] = { profileID = "P_NEW" }
trp3.profiles.P_SEEN.time = NOW + 20
trp3.profiles.P_REL.link = trp3.profiles.P_REL.link -- unchanged
local deletedID = "P_OLD"
trp3.profiles[deletedID] = nil
trp3.character["Old-Realm"].profileID = nil

Archive.Update(archive, trp3, session)
Check(archive.profiles.P_NEW ~= nil, "new profiles reach the archive")
Check(archive.profiles.P_BOTH.characteristics.FN == "Both, TRP3 newer", "the archive takes TRP3's newer version")
Check(archive.profiles.P_SEEN.time == NOW + 20, "profiles met again are updated in the archive")
Check(archive.profiles.P_OLD == nil and archive.character["Old-Realm"] == nil, "profiles deleted during the session leave the archive")

local protected = Archive.GetProtectedProfileIDs({ mine = { relation = { P_REL = "FRIEND" } } }, {})
local removed = Archive.Trim(trp3, session, protected)
Check(trp3.profiles.P_REL ~= nil and trp3.character["Rel-Realm"] ~= nil, "profiles with relations stay in TRP3's file, with their characters")
Check(trp3.profiles.P_SEEN ~= nil, "archive profiles met again this session stay in TRP3's file")
Check(trp3.profiles.P_NEW ~= nil and trp3.profiles.P_OWN ~= nil, "TRP3's own and new profiles stay")
Check(trp3.profiles.P_IGN == nil and trp3.companion.C_OLD == nil, "archive-only entries are taken back out")
Check(trp3.character["Ignored-Realm"] ~= nil, "TRP3's ignored characters are left alone")
Check(removed.profiles >= 1, "trim reports what it removed")

---------------------------------------------------------------------------
print("Archive file storage")
---------------------------------------------------------------------------

local Storage = ns.Storage
local INFO = { schema = 25, now = NOW, addonVersion = "test" }

-- a bigger archive so it spans many blocks
local big = Archive.NewDirectory()
for i = 1, 2000 do
	local profileID = "P" .. i
	big.profiles[profileID] = Profile("Player " .. i, OLD + i, "Char" .. i .. "-Realm")
	big.character["Char" .. i .. "-Realm"] = { profileID = profileID, guild = "G" .. (i % 7) }
end
for i = 1, 300 do
	big.companion["C" .. i] = { data = { NA = "Pet " .. i, v = 1 }, PE = { v = 1 }, links = { ["Char" .. i .. "-Realm_Pet"] = 1 } }
end

local emptyArchive, emptyStore = Storage.Load(nil)
local first, firstSummary = Storage.Save(big, emptyStore, Storage.Snapshot(emptyArchive), INFO)
Check(firstSummary.rewritten == firstSummary.blocks, ("the first save writes every block (%d)"):format(firstSummary.blocks))

local loaded, store = Storage.Load(first)
Check(DeepEqual(loaded, big), "saving and loading keeps the whole archive exactly")

-- a session: one profile seen again, one new character, one companion deleted
local snapshot = Storage.Snapshot(loaded)
loaded.profiles.P5.time = NOW
loaded.character["Newbie-Realm"] = { profileID = "P5" }
loaded.profiles.P5.link["Newbie-Realm"] = 1
loaded.companion.C9 = nil
local second, secondSummary = Storage.Save(loaded, store, snapshot, INFO)
Check(secondSummary.rewritten <= 3, ("only changed blocks are rewritten (%d of %d)"):format(secondSummary.rewritten, secondSummary.blocks))
local reloaded = Storage.Load(second)
Check(reloaded.profiles.P5.time == NOW and reloaded.character["Newbie-Realm"] and reloaded.companion.C9 == nil
	and H.Count(reloaded.profiles) == 2000, "changes are saved and nothing else is lost")

-- a damaged block is kept, never thrown away
local damaged = {}
for k, v in pairs(second) do damaged[k] = v end
damaged.profiles = {}
for i, text in ipairs(second.profiles) do damaged.profiles[i] = text end
damaged.profiles[1] = "return{[\"broken"
local partial, damagedStore = Storage.Load(damaged)
Check(damagedStore.unreadableCount == 1 and H.Count(partial.profiles) < 2000, "an unreadable block is reported")
local kept = Storage.Save(partial, damagedStore, Storage.Snapshot(partial), INFO)
Check(kept.unreadable and kept.unreadable.profiles[1] == "return{[\"broken", "the unreadable block is saved again untouched")

-- every FULL_WRITE_EVERY logouts everything is rewritten
local _, lateStore = Storage.Load(second)
lateStore.meta.writesSinceFull = Storage.FULL_WRITE_EVERY - 1
local lateArchive = Storage.Load(second)
local full, fullSummary = Storage.Save(lateArchive, lateStore, Storage.Snapshot(lateArchive), INFO)
Check(fullSummary.rewritten == fullSummary.blocks and full.writesSinceFull == 0, "a periodic full rewrite happens")

local _, newerStore = Storage.Load({ format = 99, profiles = {} })
Check(newerStore.unknownFormat, "an archive file from a newer version is left alone")

---------------------------------------------------------------------------
print("Negative zero")
---------------------------------------------------------------------------

-- Lua 5.1 keeps one constant per function for 0 and -0, so the first zero in a chunk decides the
-- sign of them all. tonumber is used here because a -0 literal would do the same to this file.
local NEGATIVE_ZERO = tonumber("-0")
local function IsNegativeZero(n) return n == 0 and 1 / n < 0 end
local function IsPositiveZero(n) return n == 0 and 1 / n > 0 end

local poisoned = assert(loadstring('return{[1]=-0,[2]=0,}'))()
Check(IsNegativeZero(poisoned[2]), "the problem exists: a -0 turns a later 0 in the same chunk into -0")

Check(IsPositiveZero(Serializer.Parse(Serializer.SerializeBlock({ a = NEGATIVE_ZERO })).a)
	and not Serializer.SerializeBlock({ a = NEGATIVE_ZERO }):find("-0", 1, true), "-0 is written as 0")
local parsed = Serializer.Parse('return{["a"]=-0,["b"]=0,["c"]=-2,}')
Check(IsPositiveZero(parsed.a) and IsPositiveZero(parsed.b) and parsed.c == -2, "an export holding -0 is read as 0")

local OLD_BLOCK = 'return{["P1"]={["RS"]=-0,["V2"]=0,["time"]=5,["DE"]="a]=-0,b",["characteristics"]={["FN"]="Old",},},}'
local oldArchive = Storage.Load({ format = ns.ARCHIVE_FORMAT, profiles = { OLD_BLOCK }, character = {}, companion = {} })
local oldProfile = oldArchive.profiles.P1
Check(IsPositiveZero(oldProfile.RS) and IsPositiveZero(oldProfile.V2), "a block saved with -0 no longer spreads it when read")
Check(oldProfile.time == 5 and oldProfile.DE == "a]=-0,b", "the rest of that block is read unchanged")

---------------------------------------------------------------------------
print("Secret values")
---------------------------------------------------------------------------

-- Stands in for a game secret: reading it as text is an error, as comparing a secret is in game.
local SECRET = setmetatable({}, { __tostring = function() error("a secret value was read") end })
local secretEnv = H.NewEnvironment()
secretEnv.issecretvalue = function(value) return value == SECRET end
local secretNs = H.LoadAddon(secretEnv, "TRP3_DirectoryKeeper")
local SecretStorage = secretNs.Storage

local secretBase = Archive.NewDirectory()
secretBase.profiles.P1 = { characteristics = { FN = "Seen" }, time = OLD, link = { ["Seen-Realm"] = 1 } }
secretBase.character["Seen-Realm"] = { profileID = "P1", guild = "Plain" }
local secretFirst = SecretStorage.Save(secretBase, select(2, SecretStorage.Load(nil)),
	SecretStorage.Snapshot(Archive.NewDirectory()), INFO)
local secretLoaded, secretStore = SecretStorage.Load(secretFirst)
local secretSnapshot = SecretStorage.Snapshot(secretLoaded)
secretLoaded.character["Seen-Realm"].guild = SECRET
local secretSaved, secretSummary = pcall(SecretStorage.Save, secretLoaded, secretStore, secretSnapshot, INFO)
Check(secretSaved, "a secret guild name does not stop the archive being saved")
Check(secretSaved and secretSummary.character ~= nil
	and SecretStorage.Load(secretSummary).character["Seen-Realm"].profileID == "P1"
	and SecretStorage.Load(secretSummary).character["Seen-Realm"].guild == nil, "the secret is left out and the character is kept")

---------------------------------------------------------------------------
print("Game clients")
---------------------------------------------------------------------------

Check(Exchange.GAME_FOLDER == "_retail_", "Retail uses the _retail_ folder (WOW_PROJECT_CAMELOT does not exist there)")
local foreverEnv = H.NewEnvironment()
foreverEnv.WOW_PROJECT_CAMELOT, foreverEnv.WOW_PROJECT_ID = 18, 18
Check(H.LoadAddon(foreverEnv, "TRP3_DirectoryKeeper").Exchange.GAME_FOLDER == "_forever_", "WoW Forever uses the _forever_ folder")

for _, addon in ipairs({ "TRP3_DirectoryKeeper", "TRP3_DirectoryKeeper_Archive", "TRP3_DirectoryKeeper_Exchange" }) do
	local toc = assert(io.open(addon .. "/" .. addon .. ".toc", "rb"))
	local interface = toc:read("*a"):match("## Interface: ([^\r\n]*)")
	toc:close()
	Check(interface == "120105, 16001", addon .. " lists the Retail and WoW Forever interface versions")
end

---------------------------------------------------------------------------
print("Import planning")
---------------------------------------------------------------------------

env.__now = NOW
local mine = {
	profiles = { P_MINE = Profile("Mine", NOW, "Known-Realm") },
	character = { ["Known-Realm"] = { profileID = "P_MINE" } },
	companion = {},
	blockList = { ["Blocked-Realm"] = "reason" },
}
local theirs = {
	profiles = {
		P_MINE = Profile("Their copy of a profile I know", NOW, "Known-Realm", "Alt-Realm"),
		P_NEW1 = Profile("New one", NOW + 99999, "New1-Realm"),
		P_BLOCK = Profile("Blocked", NOW, "Blocked-Realm"),
		P_BAD = { characteristics = { FN = "Bad" }, time = NOW, link = { ["Bad-Realm"] = 1 }, extra = function() end },
		["0602151111|n?Jr"] = Profile("Old-style profile ID", NOW, "Pipe-Realm"),
	},
	character = {
		["Known-Realm"] = { profileID = "P_MINE" },
		["Alt-Realm"] = { profileID = "P_MINE", client = "Total RP 3" },
		["New1-Realm"] = { profileID = "P_NEW1", guild = "Guild" },
		["Blocked-Realm"] = { profileID = "P_BLOCK" },
		["Bad|cffff0000-Realm"] = { profileID = "P_NEW1" },
		["Bad-Realm"] = { profileID = "P_BAD" },
		["Pipe-Realm"] = { profileID = "0602151111|n?Jr" },
	},
	companion = {
		C_NEW = { data = { NA = "Pet" }, PE = {}, links = { ["New1-Realm_Pet"] = 1, ["Stranger-Realm_Pet"] = 1 } },
	},
}

local exportJob = coroutine.create(function()
	return Exchange.BuildExport(theirs, {}, { trp3Version = "3.5.4", schema = 25, now = NOW })
end)
local _, export = coroutine.resume(exportJob)
Check(Exchange.CheckHeader(export, 25, NOW) == true, "export header is accepted")
Check(not Exchange.CheckHeader(export, 26, NOW), "a different TRP3 data format is refused")
local tampered = {}
for k, v in pairs(export) do tampered[k] = v end
tampered.exportedAt = NOW + 10 * 86400
Check(not Exchange.CheckHeader(tampered, 25, NOW), "an export dated in the future is refused")

local planJob = coroutine.create(function() return Exchange.Plan(export, mine, mine.blockList, nil) end)
local _, plan, report = coroutine.resume(planJob)
Check(plan.characters["Known-Realm"] == nil, "characters I already have are skipped")
Check(plan.characters["Alt-Realm"] ~= nil and plan.profiles.P_MINE == nil, "a new character of a known profile is linked to my copy")
Check(plan.characters["Blocked-Realm"] == nil and report.ignored == 1, "characters on my ignore list are skipped")
Check(plan.characters["New1-Realm"] ~= nil and plan.profiles.P_NEW1 ~= nil, "new characters and profiles are planned")
Check(plan.profiles.P_NEW1.time == NOW, "last-seen dates are capped at the export date")
Check(plan.characters["Bad|cffff0000-Realm"] == nil, "character IDs with escape codes are rejected")
Check(plan.profiles["0602151111|n?Jr"] ~= nil and plan.characters["Pipe-Realm"] ~= nil, "old-style profile IDs with symbols are accepted")
Check(report.invalid == 0, "nothing valid is counted as invalid")
Check(plan.companions.C_NEW and plan.companions.C_NEW.links["New1-Realm_Pet"] and not plan.companions.C_NEW.links["Stranger-Realm_Pet"],
	"companions keep only links to owners in the directory")

local importArchive = Archive.NewDirectory()
local importSession = Archive.Merge(mine, importArchive, mine.blockList, NOW, {})
Exchange.Apply(plan, mine, importArchive, importSession)
Check(mine.profiles.P_MINE.link["Alt-Realm"] == 1 and mine.profiles.P_MINE.characteristics.FN == "Mine",
	"my copy of a known profile is never changed, only linked")
Check(mine.profiles.P_NEW1 ~= nil and importArchive.profiles.P_NEW1 ~= nil, "imported entries are shown and archived")
Archive.Update(importArchive, mine, importSession)
Archive.Trim(mine, importSession, {})
Check(mine.profiles.P_NEW1 == nil and importArchive.profiles.P_NEW1 ~= nil, "imported entries are not saved into TRP3's own file")
Check(mine.character["Alt-Realm"] ~= nil, "a character linked to my own profile stays in TRP3's file")

---------------------------------------------------------------------------
print("Fingerprints")
---------------------------------------------------------------------------

-- Any change to an entry's own fields must reach the file, also for entries only the archive holds.
local function SaveAfter(change)
	local fpArchive, fpStore = Storage.Load(first)
	local fpSnapshot = Storage.Snapshot(fpArchive)
	change(fpArchive)
	local fpSaved, fpSummary = Storage.Save(fpArchive, fpStore, fpSnapshot, INFO)
	return (Storage.Load(fpSaved)), fpSummary
end

local flagged, flaggedSummary = SaveAfter(function(a) a.profiles.P7.hasMatureContent = true end)
Check(flagged.profiles.P7.hasMatureContent == true and flaggedSummary.rewritten == 1, "a flag set on a profile is saved")
local zoned = SaveAfter(function(a) a.profiles.P7.zone = "Stormwind" end)
Check(zoned.profiles.P7.zone == "Stormwind", "a profile field without a version number is saved")
local raced, racedSummary = SaveAfter(function(a)
	a.character["Char7-Realm"].race = "Orc"
	a.character["Char8-Realm"].classID = 3
end)
Check(raced.character["Char7-Realm"].race == "Orc" and raced.character["Char8-Realm"].classID == 3 and racedSummary.rewritten <= 2,
	"character fields such as race and class are saved")
local cleared = SaveAfter(function(a) a.character["Char7-Realm"].guild = nil end)
Check(cleared.character["Char7-Realm"].guild == nil, "a removed field is saved")
local versioned = SaveAfter(function(a) a.companion.C7.data.v = 2; a.companion.C7.data.NA = "Renamed" end)
Check(versioned.companion.C7.data.NA == "Renamed", "a new version of a table inside an entry is saved")

-- TRP3's own copy of an entry is a different table with the same contents; that is not a change.
local _, copiedSummary = SaveAfter(function(a)
	for _, section in ipairs(ns.SECTIONS) do
		for key, entry in pairs(a[section]) do
			local keys, copy = {}, {}
			for field in pairs(entry) do keys[#keys + 1] = field end
			for i = #keys, 1, -1 do copy[keys[i]] = entry[keys[i]] end -- fields added in another order
			a[section][key] = copy
		end
	end
end)
Check(copiedSummary.rewritten == 0, "identical copies of every entry rewrite no block")

---------------------------------------------------------------------------
print("Malformed entries in TRP3's directory")
---------------------------------------------------------------------------

local function BrokenDirectory()
	local directory = {
		profiles = { P_OWN = Profile("Own", NOW - 3600, "Own-Realm"), P_JUNK = 5 },
		character = { ["Own-Realm"] = { profileID = "P_OWN" }, ["Junk-Realm"] = 1, ["Junk2-Realm"] = "x" },
		companion = { C_JUNK = true },
		blockList = {},
	}
	local stored = {
		profiles = { P_OLD = Profile("Old friend", OLD, "Old-Realm"), P_SEEN = Profile("Met again", OLD, "Seen-Realm") },
		character = { ["Old-Realm"] = { profileID = "P_OLD" }, ["Seen-Realm"] = { profileID = "P_SEEN" }, ["Junk-Realm"] = { profileID = "P_OLD" } },
		companion = { C_OLD = { data = { NA = "Pet" }, PE = {}, links = { ["Old-Realm_Pet"] = 1 } } },
	}
	return directory, stored
end

local broken, brokenArchive = BrokenDirectory()
local brokenMerged, brokenSession = pcall(Archive.Merge, broken, brokenArchive, broken.blockList, NOW, {})
Check(brokenMerged and broken.profiles.P_OLD ~= nil, "merging works around entries that are not tables")
broken.profiles.P_SEEN.time = NOW + 5
Check(pcall(Archive.Update, brokenArchive, broken, brokenSession), "updating the archive works around them")
Check(brokenArchive.profiles.P_JUNK == nil and brokenArchive.character["Junk2-Realm"] == nil and brokenArchive.companion.C_JUNK == nil,
	"they are not taken into the archive")
Check(pcall(Storage.Save, brokenArchive, select(2, Storage.Load(nil)), Storage.Snapshot(Archive.NewDirectory()), INFO),
	"the archive can still be saved")
local brokenTrimmed = pcall(Archive.Trim, broken, brokenSession, {})
Check(brokenTrimmed and broken.profiles.P_OLD == nil and broken.character["Old-Realm"] == nil and broken.companion.C_OLD == nil,
	"trimming works around them and takes the archive's entries back out")
Check(broken.profiles.P_SEEN ~= nil and broken.profiles.P_OWN ~= nil and broken.profiles.P_JUNK == 5 and broken.character["Junk-Realm"] == 1,
	"TRP3's own entries stay as they were, whatever they are")

-- The fallback used when trimming fails anyway.
local fallback, fallbackArchive = BrokenDirectory()
local fallbackSession = Archive.Merge(fallback, fallbackArchive, fallback.blockList, NOW, {})
fallback.profiles.P_SEEN.time = NOW + 5
fallbackArchive.profiles.P_REL = Profile("Has a relation", OLD, "Rel-Realm")
fallbackArchive.character["Rel-Realm"] = { profileID = "P_REL" }
fallback.profiles.P_REL, fallback.character["Rel-Realm"] = fallbackArchive.profiles.P_REL, fallbackArchive.character["Rel-Realm"]
fallbackSession.injectedProfiles.P_REL, fallbackSession.injectedCharacters["Rel-Realm"] = true, true
local fallbackRemoved = Archive.RemoveInjected(fallback, fallbackSession, { P_REL = true })
Check(fallback.profiles.P_OLD == nil and fallback.character["Old-Realm"] == nil and fallback.companion.C_OLD == nil,
	"the fallback takes the archive's entries back out")
Check(fallback.profiles.P_SEEN ~= nil and fallback.character["Seen-Realm"] ~= nil, "the fallback keeps profiles seen this session")
Check(fallback.profiles.P_REL ~= nil and fallback.character["Rel-Realm"] ~= nil, "the fallback keeps profiles with relations")
Check(fallback.profiles.P_OWN ~= nil and fallback.character["Own-Realm"] ~= nil and fallback.profiles.P_JUNK == 5,
	"the fallback leaves TRP3's own entries alone")
Check(fallbackRemoved.profiles == 1 and fallbackRemoved.characters == 1 and fallbackRemoved.companions == 1, "the fallback reports what it removed")

---------------------------------------------------------------------------
print("A missing or smaller archive file")
---------------------------------------------------------------------------

Check(Storage.CheckAgainstLastSave(nil, Archive.NewDirectory(), nil) == nil, "a first start is not a problem")
Check(Storage.CheckAgainstLastSave(nil, Archive.NewDirectory(), { profiles = 0 }) == nil, "an archive that was empty may still be empty")
Check(Storage.CheckAgainstLastSave(nil, Archive.NewDirectory(), { profiles = 2000 }) == "missing", "a missing archive is noticed")
Check(Storage.CheckAgainstLastSave({}, Archive.NewDirectory(), { profiles = 2000 }) == "missing", "an empty archive file is noticed")
Check(Storage.CheckAgainstLastSave(first, loaded, { profiles = 2000 }) == nil, "the archive that was saved is accepted")
Check(Storage.CheckAgainstLastSave(first, loaded, { profiles = 3500 }) == nil, "an older copy with most of the profiles is accepted")
Check(Storage.CheckAgainstLastSave(first, loaded, { profiles = 4001 }) == "smaller", "an archive with fewer than half the profiles is noticed")

-- Whole sessions: saved variables are copied between them, as saving and loading separates them.
local function Copy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for k, v in pairs(value) do copy[k] = Copy(v) end
	return copy
end

local function Session(state, now, during)
	local sessionEnv = H.NewEnvironment()
	sessionEnv.__now = now
	sessionEnv.TRP3_Register = Copy(state.register)
	sessionEnv.TRP3_Flyway = { currentBuild = 25 }
	sessionEnv.TRP3_Profiles, sessionEnv.TRP3_Notes = {}, {}
	sessionEnv.TRP3DK_Archive, sessionEnv.TRP3DK_State = Copy(state.archive), Copy(state.keeperState)
	local sessionNs = H.LoadAddon(sessionEnv, "TRP3_DirectoryKeeper")
	H.FireEvent(sessionEnv, "ADDON_LOADED", "TRP3_DirectoryKeeper")
	H.FireEvent(sessionEnv, "PLAYER_ENTERING_WORLD")
	local result = { shown = H.Count(sessionEnv.TRP3_Register.profiles), pauseReason = sessionNs.status.pauseReason }
	if during then during(sessionEnv, sessionNs) end
	H.FireEvent(sessionEnv, "PLAYER_LOGOUT")
	result.register, result.archive, result.keeperState = sessionEnv.TRP3_Register, sessionEnv.TRP3DK_Archive, sessionEnv.TRP3DK_State
	result.chat, result.popups = table.concat(sessionEnv.__chat, "\n"), sessionEnv.__popups
	return result
end

local function Directory(count)
	local directory = { profiles = {}, character = {}, companion = {}, blockList = {} }
	for i = 1, count do
		directory.profiles["P" .. i] = Profile("Player " .. i, NOW, "Char" .. i .. "-Realm")
		directory.character["Char" .. i .. "-Realm"] = { profileID = "P" .. i }
	end
	return directory
end

local s1 = Session({ register = Directory(50) }, NOW + 60)
Check(s1.archive.counts.profiles == 50 and s1.keeperState.archive.profiles == 50 and s1.keeperState.archive.savedAt == s1.archive.savedAt,
	"what the archive holds is recorded in the addon's own file at every save")

local s2 = Session({ register = Directory(2), archive = nil, keeperState = s1.keeperState }, NOW + 20 * 86400)
Check(s2.pauseReason ~= nil and s2.archive == nil, "when the archive file was not read, the archive is paused and nothing is written in its place")
Check(s2.chat:find("Archive.lua.bak", 1, true) and #s2.popups == 1 and s2.popups[1].text:find("Do not log out", 1, true),
	"the player is told to save the game's backup copy before logging out")
Check(s2.keeperState.archive.profiles == 50 and s2.shown == 2, "the record is kept, so the warning comes back until it is settled")

local s3 = Session({ register = Directory(2), archive = s1.archive, keeperState = s2.keeperState }, NOW + 21 * 86400)
Check(s3.pauseReason == nil and s3.shown == 50 and s3.archive.counts.profiles == 50, "with the archive file restored, everything carries on")

local s4 = Session({ register = Directory(2), archive = nil, keeperState = s1.keeperState }, NOW + 20 * 86400, function(sessionEnv)
	H.Slash(sessionEnv, "accept")
end)
local s5 = Session({ register = s4.register, archive = s4.archive, keeperState = s4.keeperState }, NOW + 21 * 86400)
Check(s4.keeperState.archive == nil and s5.pauseReason == nil and s5.archive.counts.profiles == 2 and s5.keeperState.archive.profiles == 2,
	"/tdk accept starts again from what is there")

local sOld = Session({ register = Directory(2), archive = s1.archive, keeperState = { lastLogout = s1.keeperState.lastLogout } }, NOW + 86400)
Check(sOld.pauseReason == nil and sOld.shown == 50, "an archive from before the record existed is used as it is")

-- A logout where TRP3's directory holds something the trim cannot handle still hands TRP3 its own directory back.
local s6 = Session({ register = Directory(0), archive = s1.archive, keeperState = s1.keeperState }, NOW + 20 * 86400, function(_, sessionNs)
	sessionNs.Archive.Trim = function() error("trim failed") end
end)
Check(H.Count(s6.register.profiles) == 0 and s6.keeperState.lastLogout.trimFallback == true and s6.keeperState.lastLogout.trimmed == true,
	"if trimming fails, the archive's entries are still taken out of TRP3's directory")
Check(s6.archive.counts.profiles == 50, "and the archive is still saved")
local s7 = Session({ register = s6.register, archive = s6.archive, keeperState = s6.keeperState }, NOW + 21 * 86400)
Check(s7.chat:find("trim failed", 1, true) ~= nil, "a failure at logout is reported at the next login")

print(H.Failures() == 0 and "\nAll unit tests passed." or ("\n" .. H.Failures() .. " unit test(s) FAILED."))
os.exit(H.Failures() == 0 and 0 or 1)
