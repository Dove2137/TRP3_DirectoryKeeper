-- TRP3 Directory Keeper
-- Startup, logout and the /tdk command.
--
--   ADDON_LOADED          Read the archive file and note every entry's fingerprint.
--   PLAYER_ENTERING_WORLD Total RP 3 has loaded and run its own cleanup and purge. Add the archive to
--                         its directory, add the buttons, warn when TRP3's own file is near the limit.
--   PLAYER_LOGOUT         Update the archive, hand TRP3 back its own directory, write the archive file.
--                         Registered late so Total RP 3's own logout handlers run first.

local ADDON_NAME, ns = ...

local Archive, Storage = ns.Archive, ns.Storage
local format = string.format
local status = ns.status

--- Notes what the archive holds, in this addon's own file, to check the archive file against at the next login.
local function RecordArchive(savedAt, counts)
	TRP3DK_State.archive = {
		savedAt = savedAt, profiles = counts.profiles, characters = counts.characters, companions = counts.companions,
	}
end

local function OnAddonLoaded()
	if type(TRP3DK_State) ~= "table" then TRP3DK_State = {} end
	local started = debugprofilestop()
	ns.archive, ns.store = Storage.Load(_G[ns.ARCHIVE_VARIABLE])
	ns.snapshot = Storage.Snapshot(ns.archive)
	status.loadMs = debugprofilestop() - started
	if ns.store.unreadableCount > 0 then
		ns.Print("%d block(s) of the archive could not be read; they are kept untouched in the archive file.", ns.store.unreadableCount)
	end

	-- TRP3DK_State is saved in a different file than the archive, so it still knows what the archive
	-- held at the last save when the archive's own file was not read (see Storage.CheckAgainstLastSave).
	if not ns.store.unknownFormat then
		status.archiveProblem = Storage.CheckAgainstLastSave(_G[ns.ARCHIVE_VARIABLE], ns.archive, TRP3DK_State.archive)
		if not status.archiveProblem and type(TRP3DK_State.archive) ~= "table" and not Archive.IsEmpty(ns.archive) then
			RecordArchive(ns.store.meta.savedAt, Archive.Counts(ns.archive)) -- an archive from before this record existed
		end
	end
end

--- The reason shown when the archive read at login does not match the last save.
local function DescribeArchiveProblem()
	local lastSave = TRP3DK_State.archive
	if status.archiveProblem == "missing" then
		return format("the archive file is empty or could not be read, but it held %d profiles when it was last saved (%s)",
			lastSave.profiles, ns.FormatDate(lastSave.savedAt))
	end
	return format("the archive file holds %d profiles, but it held %d when it was last saved (%s)",
		ns.CountKeys(ns.archive.profiles), lastSave.profiles, ns.FormatDate(lastSave.savedAt))
end

-- The game renames a saved-variables file to .bak before writing it again, so right after a failed
-- read the .bak is the last good copy, until the next logout or reload replaces it.
local function WarnAboutArchiveProblem()
	local text = format("|cffff2020Do not log out or reload yet.|r The archive is paused because %s.\n\n"
		.. "The game's backup of the previous save may still hold your archive, and is replaced at your next logout or reload. "
		.. "Copy this file to a safe place now:\n\nWorld of Warcraft\\%s\\WTF\\Account\\\n|cffff2020<YOUR ACCOUNT FOLDER>|r\\SavedVariables\\\n"
		.. "|cff20ff20TRP3_DirectoryKeeper_Archive.lua.bak|r\n\n"
		.. "Then close the game and put the copy back in that folder as TRP3_DirectoryKeeper_Archive.lua.\n\n"
		.. "To carry on with the archive as it is now instead, type |cff66ccff/tdk accept|r.",
		DescribeArchiveProblem(), ns.Exchange.GAME_FOLDER)
	ns.Print((text:gsub("\n+", " ")))
	ns.UI.Alert(text)
end

--- Returns a reason when the archive must be left alone this session, or nil.
local function GetPauseReason()
	local directory = TRP3_Register
	if type(directory) ~= "table" or type(directory.profiles) ~= "table" or type(directory.character) ~= "table"
		or type(directory.companion) ~= "table" then
		return "Total RP 3's directory is not available"
	end
	local schema = TRP3_Flyway and TRP3_Flyway.currentBuild
	if not schema then
		return "Total RP 3 did not finish loading"
	end
	if ns.store.unknownFormat then
		return "the archive file was written by a newer version of TRP3 Directory Keeper. Update the addon; until then the archive is left untouched"
	end
	if status.archiveProblem then
		return DescribeArchiveProblem()
	end
	local savedSchema = ns.store.meta.schema
	if savedSchema and savedSchema ~= schema and not Archive.IsEmpty(ns.archive) then
		return format("the archive was saved with Total RP 3 data format %s, but Total RP 3 now uses %s. Update TRP3 Directory Keeper; until then the archive is left untouched", tostring(savedSchema), tostring(schema))
	end
	return nil
end

local function WarnIfNearLimit(profileCount)
	local usage = ns.EstimateUsage(profileCount)
	status.ownUsage = usage
	if usage >= ns.WARNING_RATIO then
		ns.Print("|cffff9900Total RP 3's own directory file is at about %d%% of the saved-variables limit (%d profiles).|r If it goes over, the game cannot load that file; your archive still keeps and shows everyone. Total RP 3's purge setting (Settings > Directory) controls how large its own file gets.",
			math.floor(usage * 100 + 0.5), profileCount)
	end
end

local function OnLoginComplete()
	local reason = GetPauseReason()
	if reason then
		status.pauseReason = reason
		if status.archiveProblem then
			WarnAboutArchiveProblem()
		else
			ns.Print("|cffff9900The archive is paused:|r %s.", reason)
		end
		return
	end

	local lastLogout = TRP3DK_State.lastLogout
	if type(lastLogout) == "table" and lastLogout.error then
		ns.Print("|cffff9900At your last logout the archive could not be brought up to date|r (%s). It was saved as it was before that session.",
			tostring(lastLogout.error))
	end

	local started = debugprofilestop()
	ns.session = {}
	local ok, err = pcall(Archive.Merge, TRP3_Register, ns.archive, TRP3_Register.blockList, time(), ns.session)
	status.mergeMs = debugprofilestop() - started
	if ok then
		ns.session.complete = true
	else
		status.error = err
		ns.Print("|cffff0000Adding the archive to the directory failed:|r %s. The archive is not changed this session.", tostring(err))
	end
	status.added = ns.CountKeys(ns.session.injectedProfiles)

	WarnIfNearLimit(ns.session.ownProfiles or ns.CountKeys(TRP3_Register.profiles))
end

local function OnLogout()
	local session = ns.session
	if not session then return end -- paused: nothing was added, so there is nothing to undo
	local started = debugprofilestop()

	local updated, failure = false, nil
	if session.complete then
		updated, failure = pcall(Archive.Update, ns.archive, TRP3_Register, session)
	end

	-- Always hand TRP3 back its own directory, even when the archive could not be updated. If the
	-- archive's entries stayed in it, TRP3's own file could grow past the saved-variables limit.
	local protectedFound, protected = pcall(Archive.GetProtectedProfileIDs, TRP3_Profiles, TRP3_Notes)
	if not protectedFound then protected = {} end
	local trimmed, removed = pcall(Archive.Trim, TRP3_Register, session, protected)
	local trimFallback = not trimmed
	if trimFallback then
		failure = failure or removed
		trimmed, removed = pcall(Archive.RemoveInjected, TRP3_Register, session, protected)
	end

	-- If anything failed, TRP3DK_Archive is left as it was loaded, so the game saves the previous
	-- archive unchanged.
	local written, saved, summary = false, nil, nil
	if updated then
		written, saved, summary = pcall(Storage.Save, ns.archive, ns.store, ns.snapshot, {
			schema = TRP3_Flyway.currentBuild, now = time(), addonVersion = ns.VERSION,
		})
		if written then
			_G[ns.ARCHIVE_VARIABLE] = saved
			RecordArchive(saved.savedAt, saved.counts)
		else
			failure = failure or saved
		end
	end

	TRP3DK_State.lastLogout = {
		at = time(),
		ms = debugprofilestop() - started,
		archiveWritten = written,
		blocksRewritten = written and summary.rewritten or nil,
		blocks = written and summary.blocks or nil,
		trimmed = trimmed,
		trimFallback = trimFallback or nil,
		removed = trimmed and removed or nil,
		trp3Profiles = ns.CountKeys(TRP3_Register.profiles),
		error = failure and tostring(failure) or nil, -- shown at the next login
	}
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			self:UnregisterEvent("ADDON_LOADED")
			OnAddonLoaded()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		self:UnregisterEvent("PLAYER_ENTERING_WORLD")
		OnLoginComplete()
		if not ns.UI.CreateDirectoryButtons() then
			ns.Print("The Import and Export buttons could not be added to the directory (Total RP 3 changed its layout). Use /tdk import and /tdk export instead.")
		end
		self:RegisterEvent("PLAYER_LOGOUT")
	elseif event == "PLAYER_LOGOUT" then
		OnLogout()
	end
end)

---------------------------------------------------------------------------
-- /tdk
---------------------------------------------------------------------------

local function PrintStatus()
	ns.Print("version %s, %s", ns.VERSION, status.pauseReason and ("|cffff9900paused|r: " .. status.pauseReason) or "active")
	if type(TRP3_Register) == "table" then
		local shown = Archive.Counts(TRP3_Register)
		ns.Print("directory shown in Total RP 3: %d profiles, %d characters, %d companions (%d profiles from the archive)",
			shown.profiles, shown.characters, shown.companions, status.added or 0)
	end
	if ns.archive then
		local counts = Archive.Counts(ns.archive)
		ns.Print("archive: %d profiles, %d characters, %d companions (last saved %s)",
			counts.profiles, counts.characters, counts.companions, ns.FormatDate(ns.store.meta.savedAt))
	end
	if ns.session and ns.session.ownProfiles then
		ns.Print("Total RP 3's own file: %d profiles at login, about %d%% of the saved-variables limit",
			ns.session.ownProfiles, math.floor((status.ownUsage or 0) * 100 + 0.5))
	end
	local lastLogout = TRP3DK_State and TRP3DK_State.lastLogout
	ns.Print("timing: archive read in %d ms, added in %d ms; last logout took %s",
		status.loadMs or 0, status.mergeMs or 0, lastLogout and format("%d ms", lastLogout.ms) or "n/a")
	if status.error then
		ns.Print("|cffff0000error:|r %s", tostring(status.error))
	end
end

SLASH_TRP3DIRECTORYKEEPER1 = "/tdk"
SlashCmdList.TRP3DIRECTORYKEEPER = function(message)
	local command = strtrim(message or ""):lower()
	if command == "export" then
		ns.Exchange.StartExport()
	elseif command == "import" then
		ns.Exchange.StartImport()
	elseif command == "accept" then
		if not status.archiveProblem then
			ns.Print("There is nothing to accept: the archive was read normally.")
		else
			TRP3DK_State.archive = nil
			ns.Print("The archive will be used as it is now. Reload (/reload) to continue.")
		end
	elseif command == "" or command == "status" then
		PrintStatus()
	else
		ns.Print("/tdk - status, /tdk export - export your directory, /tdk import - import a received export")
	end
end
