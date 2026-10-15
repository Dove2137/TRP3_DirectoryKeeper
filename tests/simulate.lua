-- Session simulation on real saved-variables files.
--
--   lua5.1 tests/simulate.lua <totalRP3_Data.lua> <totalRP3.lua> <work folder>
--
-- Copies the two Total RP 3 files into <work folder>/A (player A), then plays several sessions:
-- the first login with Directory Keeper, logins with TRP3's purge off and at 30 days, an export, and
-- an import into a second, small directory (<work folder>/B, player B). After every session the
-- files are written the way the game writes them and read back with Lua's own loader.
-- Never point this at your live WTF folder.

package.path = "./tests/?.lua;" .. package.path
local H = require("harness")
local Sim = require("trp3_sim")

local dataFile, profileFile, work = arg[1], arg[2], arg[3]
assert(dataFile and profileFile and work, "usage: simulate.lua <totalRP3_Data.lua> <totalRP3.lua> <work folder>")

local ADDON_DIR = "TRP3_DirectoryKeeper"
local ARCHIVE_FILE = "TRP3_DirectoryKeeper_Archive.lua"
local TRP3_VARIABLES = { "TRP3_Characters", "TRP3_Colors", "TRP3_Companions", "TRP3_Configuration", "TRP3_Flyway",
	"TRP3_MatureFilter", "TRP3_Notes", "TRP3_Presets", "TRP3_Profiles", "TRP3_SavedAutomation" }
local DAY = 86400
local Check, Count = H.Check, H.Count

local function Copy(from, to)
	local input = assert(io.open(from, "rb"))
	local output = assert(io.open(to, "wb"))
	output:write(input:read("*a"))
	input:close(); output:close()
end

local function MakeDir(path) os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul') end

local function CountRelations(env)
	local n = 0
	for _, profile in pairs(env.TRP3_Profiles or {}) do n = n + Count(profile.relation) end
	return n
end

local function Clock() return os.clock() end

--- One game session for the account folder `dir`.
local function Session(label, dir, options)
	print(("\n== %s"):format(label))
	collectgarbage()
	local env = H.NewEnvironment()
	env.__now = options.now

	-- Saved variables are read before the addons start.
	local t = Clock()
	local ok, err = H.ReadSavedVariables(dir .. "/totalRP3_Data.lua", env)
	if not ok then print("    totalRP3_Data.lua could not be loaded: " .. tostring(err)) end
	assert(H.ReadSavedVariables(dir .. "/totalRP3.lua", env))
	H.ReadSavedVariables(dir .. "/TRP3_DirectoryKeeper.lua", env)
	local archiveOk, archiveErr = H.ReadSavedVariables(dir .. "/" .. ARCHIVE_FILE, env)
	if not archiveOk and not tostring(archiveErr):find("No such file") and not tostring(archiveErr):find("cannot open") then
		print("    the archive file could not be loaded: " .. tostring(archiveErr))
	end
	env.__onLoadAddOn = function(addon)
		if addon == "TRP3_DirectoryKeeper_Exchange" then
			H.ReadSavedVariables(dir .. "/TRP3_DirectoryKeeper_Exchange.lua", env)
		end
	end
	print(("    game read the saved variables in %.1f s"):format(Clock() - t))

	local ns = H.LoadAddon(env, ADDON_DIR)
	t = Clock()
	H.FireEvent(env, "ADDON_LOADED", "TRP3_DirectoryKeeper")
	print(("    ADDON_LOADED (archive read): %.0f ms"):format((Clock() - t) * 1000))

	Sim.Login(env, options.purge, options.now) -- PLAYER_LOGIN: Total RP 3 starts and cleans up
	local trp3Own = Count(env.TRP3_Register.profiles)
	local relationsBefore = CountRelations(env)

	t = Clock()
	H.FireEvent(env, "PLAYER_ENTERING_WORLD", true, false)
	print(("    PLAYER_ENTERING_WORLD (archive added): %.0f ms"):format((Clock() - t) * 1000))

	local result = { env = env, ns = ns, trp3Own = trp3Own, relationsBefore = relationsBefore,
		shown = Count(env.TRP3_Register.profiles), shownCharacters = Count(env.TRP3_Register.character) }
	if options.during then options.during(env, ns, result) end

	t = Clock()
	H.FireEvent(env, "PLAYER_LOGOUT")
	local lastLogout = env.TRP3DK_State.lastLogout or {}
	result.blocksRewritten, result.blocks = lastLogout.blocksRewritten, lastLogout.blocks
	print(("    PLAYER_LOGOUT (archive update, trim, write): %.0f ms, %s of %s archive blocks rewritten")
		:format((Clock() - t) * 1000, tostring(result.blocksRewritten), tostring(result.blocks)))
	result.saved = Count(env.TRP3_Register.profiles)
	result.archive = ns.archive and Count(ns.archive.profiles) or 0

	-- The game writes every loaded addon's saved variables.
	t = Clock()
	H.WriteSavedVariables(dir .. "/totalRP3_Data.lua", env, { "TRP3_Register" })
	H.WriteSavedVariables(dir .. "/totalRP3.lua", env, TRP3_VARIABLES)
	H.WriteSavedVariables(dir .. "/TRP3_DirectoryKeeper.lua", env, { "TRP3DK_State" })
	H.WriteSavedVariables(dir .. "/" .. ARCHIVE_FILE, env, { "TRP3DK_Archive" })
	if env.__loaded.TRP3_DirectoryKeeper_Exchange then
		H.WriteSavedVariables(dir .. "/TRP3_DirectoryKeeper_Exchange.lua", env, { "TRP3DK_Exchange" })
	end
	print(("    game wrote the files in %.1f s"):format(Clock() - t))

	-- ...and must be able to read them back next time.
	local readable = true
	local probe = H.NewEnvironment()
	for _, name in ipairs({ "totalRP3_Data.lua", "TRP3_DirectoryKeeper.lua", ARCHIVE_FILE }) do
		local fileOk, fileErr = H.ReadSavedVariables(dir .. "/" .. name, probe)
		if not fileOk then readable = false; print("    " .. name .. ": " .. tostring(fileErr)) end
	end
	result.readable = readable
	print(("    TRP3 shows %d profiles; TRP3's own file saved %d profiles (%.1f MB); archive %d profiles (%.1f MB)")
		:format(result.shown, result.saved, H.FileSize(dir .. "/totalRP3_Data.lua") / 2^20, result.archive,
			H.FileSize(dir .. "/" .. ARCHIVE_FILE) / 2^20))
	return result
end

local NOW = os.time()
local A, B = work .. "/A", work .. "/B"
MakeDir(work); MakeDir(A); MakeDir(B)
Copy(dataFile, A .. "/totalRP3_Data.lua")
Copy(profileFile, A .. "/totalRP3.lua")
for _, f in ipairs({ "TRP3_DirectoryKeeper.lua", "TRP3_DirectoryKeeper_Exchange.lua" }) do os.remove(A .. "/" .. f); os.remove(B .. "/" .. f) end
os.remove(A .. "/" .. ARCHIVE_FILE); os.remove(B .. "/" .. ARCHIVE_FILE)

-- Session 1: first login with Directory Keeper installed; the archive does not exist yet.
local original
local s1 = Session("A1: first login with Directory Keeper, purge off", A, {
	now = NOW, purge = false,
	during = function(env, _, result)
		original = result.shown
		-- meet someone new, and meet a known player again
		env.TRP3_Register.profiles.ZZTEST_NEW = { characteristics = { FN = "Newcomer" }, time = NOW + 60, link = { ["Newcomer-ArgentDawn"] = 1 } }
		env.TRP3_Register.character["Newcomer-ArgentDawn"] = { profileID = "ZZTEST_NEW" }
		local someID = next(env.TRP3_Register.profiles)
		env.TRP3_Register.profiles[someID].time = NOW + 120
	end,
})
Check(s1.trp3Own == original, "nothing is added at the first login (the archive is still empty)")
Check(s1.archive == original + 1, "the archive holds everything, including the newcomer")
Check(s1.saved == original + 1, "with purge off, TRP3's own file keeps everything it had (nothing was added from the archive)")
Check(s1.readable, "all files can be read back")

-- Session 2: normal login, purge still off.
local s2 = Session("A2: next login, purge off, meeting two players", A, {
	now = NOW + DAY, purge = false,
	during = function(env)
		env.TRP3_Register.profiles.ZZTEST_SECOND = { characteristics = { FN = "Second" }, time = NOW + DAY + 60, link = { ["Second-ArgentDawn"] = 1 } }
		env.TRP3_Register.character["Second-ArgentDawn"] = { profileID = "ZZTEST_SECOND" }
		env.TRP3_Register.profiles.ZZTEST_NEW.time = NOW + DAY + 120
	end,
})
Check(s1.blocksRewritten == s1.blocks, ("the first logout writes the whole archive (%d blocks)"):format(s1.blocks or 0))
Check(s2.blocksRewritten and s2.blocksRewritten <= 4,
	("a normal logout rewrites only the blocks that changed (%s of %s)"):format(tostring(s2.blocksRewritten), tostring(s2.blocks)))
Check(s2.shown == s1.archive, "everyone is shown")
Check(s2.saved == s1.saved + 1, "TRP3's own file keeps everything, plus the new player")
Check(s2.readable, "all files can be read back")

-- Session 3: the player sets TRP3's purge to 30 days.
local s3 = Session("A3: TRP3 purge set to 30 days", A, { now = NOW + 2 * DAY, purge = 30 * DAY })
Check(s3.trp3Own < s2.saved, ("TRP3 purged its own directory (%d -> %d profiles)"):format(s2.saved, s3.trp3Own))
Check(s3.shown == s2.archive, "everyone is still shown after TRP3's purge (" .. s3.shown .. ")")
Check(s3.saved == s3.trp3Own, "TRP3's own file keeps only what TRP3 kept after its purge")
Check(s3.archive == s2.archive, "the archive still holds everyone")
Check(s3.blocksRewritten and s3.blocksRewritten <= 4, ("TRP3's purge does not make the archive rewrite itself (%s blocks)"):format(tostring(s3.blocksRewritten)))
Check(s3.readable, "all files can be read back")

-- Session 4: next login with purge at 30 days; relations must survive.
local s4 = Session("A4: next login, purge at 30 days", A, { now = NOW + 3 * DAY, purge = 30 * DAY })
Check(s4.relationsBefore == s3.relationsBefore, ("relations survive across logins (%d)"):format(s4.relationsBefore))
Check(s4.shown == s2.archive, "everyone is shown")
Check(s4.blocksRewritten == 0, ("a session without changes rewrites nothing (%s blocks)"):format(tostring(s4.blocksRewritten)))
Check(s4.readable, "all files can be read back")

-- Session 5: export.
local s5 = Session("A5: export", A, {
	now = NOW + 4 * DAY, purge = 30 * DAY,
	during = function(env, ns, result)
		result.selection = ns.Exchange.SelectExport(env.TRP3_Register, env.TRP3_Register.blockList)
		H.Slash(env, "export")
		H.AcceptPopup(env, "TRP3DK_CONFIRM")
		local t = os.clock()
		local frames = H.RunUpdates(env)
		print(("    export ran over %d frames in %.1f s"):format(frames, os.clock() - t))
		H.AcceptPopup(env, "TRP3DK_RELOAD")
	end,
})
local exportPath = A .. "/TRP3_DirectoryKeeper_Exchange.lua"
local exported = H.NewEnvironment()
Check(H.ReadSavedVariables(exportPath, exported), "the export file can be read back")
local counts = exported.TRP3DK_Exchange and exported.TRP3DK_Exchange.counts or {}
print(("    export file: %.1f MB, %d profiles, %d characters, %d companions"):format(H.FileSize(exportPath) / 2^20,
	counts.profiles or 0, counts.characters or 0, counts.companions or 0))
local selection = s5.selection
Check(counts.characters == #selection.characterIDs and counts.profiles == #selection.profileIDs,
	("the export contains every character and the profiles they use (%d characters, %d profiles)"):format(#selection.characterIDs, #selection.profileIDs))
Check(s5.saved == s4.saved, "exporting does not change TRP3's own file")

-- Player B: a small directory of their own (300 profiles taken from A), receives A's export.
do
	local source = H.NewEnvironment()
	assert(H.ReadSavedVariables(A .. "/totalRP3_Data.lua", source))
	local small = { profiles = {}, character = {}, companion = {}, blockList = {} }
	local taken = 0
	for characterID, character in pairs(source.TRP3_Register.character) do
		local profile = character.profileID and source.TRP3_Register.profiles[character.profileID]
		if profile and taken < 300 and not small.profiles[character.profileID] then
			small.profiles[character.profileID] = profile
			for linked in pairs(profile.link or {}) do
				small.character[linked] = source.TRP3_Register.character[linked]
			end
			taken = taken + 1
		end
	end
	small.blockList["Blockedbyb-ArgentDawn"] = "test"
	local writer = H.NewEnvironment()
	writer.TRP3_Register = small
	H.WriteSavedVariables(B .. "/totalRP3_Data.lua", writer, { "TRP3_Register" })
	writer.TRP3_Profiles = {}
	writer.TRP3_Flyway = { currentBuild = 25 }
	writer.TRP3_Notes = {}
	H.WriteSavedVariables(B .. "/totalRP3.lua", writer, TRP3_VARIABLES)
	Copy(exportPath, B .. "/TRP3_DirectoryKeeper_Exchange.lua")
end

local b1 = Session("B1: player B imports A's export", B, {
	now = NOW + 5 * DAY, purge = 30 * DAY,
	during = function(env, _, result)
		result.before = Count(env.TRP3_Register.profiles)
		H.Slash(env, "import")
		local question = H.AcceptPopup(env, "TRP3DK_IMPORT_CHECK")
		Check(question.text:find("TRP3_DirectoryKeeper_Exchange.lua", 1, true) and question.text:find("YOUR ACCOUNT FOLDER", 1, true),
			"the import first asks whether the file is in place, showing where it goes")
		local t = os.clock()
		local frames = H.RunUpdates(env)
		print(("    reading the import ran over %d frames in %.1f s"):format(frames, os.clock() - t))
		local popup = H.AcceptPopup(env, "TRP3DK_IMPORT_APPLY")
		result.report = { invalid = tonumber(popup.text:match("(%d+) invalid")) }
		result.afterImport = Count(env.TRP3_Register.profiles)
		Check(env.__reloadRequested, "the game reloads after the import")
	end,
})
Check(b1.afterImport > b1.before, ("the import adds profiles to B's directory (%d -> %d)"):format(b1.before, b1.afterImport))
Check(b1.report and b1.report.invalid == 0, "no entry of a real directory is rejected as invalid")
Check(b1.saved == b1.trp3Own, "the import does not enlarge B's own TRP3 file")
Check(b1.archive == b1.afterImport, "B's archive holds everything after the import")
Check(b1.readable, "all of B's files can be read back")

local b2 = Session("B2: player B logs in again", B, { now = NOW + 6 * DAY, purge = 30 * DAY })
Check(b2.shown == b1.afterImport, "B sees the imported directory after logging in again")
Check(b2.saved == b2.trp3Own, "B's own TRP3 file stays at its own size")

print(H.Failures() == 0 and "\nAll session checks passed." or ("\n" .. H.Failures() .. " session check(s) FAILED."))
os.exit(H.Failures() == 0 and 0 or 1)
