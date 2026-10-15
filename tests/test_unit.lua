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
	return Exchange.BuildExport(theirs, {}, { trp3Version = "3.5.1", schema = 25, now = NOW })
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

print(H.Failures() == 0 and "\nAll unit tests passed." or ("\n" .. H.Failures() .. " unit test(s) FAILED."))
os.exit(H.Failures() == 0 and 0 or 1)
