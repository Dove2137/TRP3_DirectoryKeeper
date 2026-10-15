-- TRP3 Directory Keeper
-- The archive: every directory entry ever seen, kept next to Total RP 3's own directory.
--
-- The archive is kept in its own file (see Storage.lua), so Total RP 3's own file never has to hold
-- more than TRP3 itself would save, and stays in its normal format:
--
--   Login  (after TRP3 has loaded and run its own cleanup and purge)
--          Archive entries TRP3 does not have are added to TRP3's directory in memory, so the
--          directory screen shows everyone. When both have a profile, the newer one is kept.
--   Logout (before the game writes the files)
--          1. The archive takes the latest version of everything in TRP3's directory, and drops
--             what was deleted in TRP3 during the session.
--          2. Archive entries that were only added for display, and were not met again, are
--             taken back out of TRP3's directory. TRP3 therefore saves exactly what it would have
--             saved without this addon. Profiles you have relations or notes on always stay.
--          3. The archive file is written (only the parts that changed).
--
-- Nothing here changes TRP3's settings or code; it only reads and edits TRP3_Register's tables.
-- All functions take the directories as arguments so they can be tested outside the game.

local _, ns = ...

local pairs, ipairs, next, type = pairs, ipairs, next, type
local ProfileTime, KeySet, CountKeys = ns.ProfileTime, ns.KeySet, ns.CountKeys

local Archive = {}
ns.Archive = Archive

function Archive.NewDirectory()
	return { profiles = {}, character = {}, companion = {} }
end

local function HasCharacteristics(profile)
	return type(profile.characteristics) == "table" and next(profile.characteristics) ~= nil
end

--- Owner character of a companion ID ("Owner-Realm_companion"), as TRP3 splits it.
function Archive.CompanionOwner(companionFullID)
	if type(companionFullID) ~= "string" then return nil end
	return companionFullID:match("^([^_]+)_")
end

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------

function Archive.Counts(directory)
	return {
		profiles = CountKeys(directory.profiles),
		characters = CountKeys(directory.character),
		companions = CountKeys(directory.companion),
	}
end

function Archive.IsEmpty(directory)
	return next(directory.profiles) == nil and next(directory.character) == nil and next(directory.companion) == nil
end

---------------------------------------------------------------------------
-- Protection
---------------------------------------------------------------------------

--- Profile IDs that must stay in TRP3's own file: the ones the player has relations or notes on.
--- TRP3 removes relations to profiles missing from its directory at every login (before the
--- archive is added), and its own purge never removes these profiles either.
function Archive.GetProtectedProfileIDs(ownProfiles, accountNotes)
	local protected = {}
	if type(ownProfiles) == "table" then
		for _, profile in pairs(ownProfiles) do
			if type(profile) == "table" then
				if type(profile.relation) == "table" then
					for profileID in pairs(profile.relation) do protected[profileID] = true end
				end
				if type(profile.notes) == "table" then
					for profileID in pairs(profile.notes) do protected[profileID] = true end
				end
			end
		end
	end
	if type(accountNotes) == "table" then
		for profileID in pairs(accountNotes) do protected[profileID] = true end
	end
	return protected
end

---------------------------------------------------------------------------
-- Login: add the archive to TRP3's directory
---------------------------------------------------------------------------

--- Adds archive entries to TRP3's directory (in memory) and returns the session record needed at
--- logout. The record is filled while merging, so it stays accurate even if merging stops halfway.
function Archive.Merge(directory, archive, blockList, sessionStart, session)
	session = session or {}
	session.sessionStart = sessionStart
	session.ownProfiles = CountKeys(directory.profiles)
	session.injectedProfiles = session.injectedProfiles or {}
	session.injectedCharacters = session.injectedCharacters or {}
	session.injectedCompanions = session.injectedCompanions or {}
	session.importedProfiles = session.importedProfiles or {}
	blockList = type(blockList) == "table" and blockList or {}

	local profiles, characters, companions = directory.profiles, directory.character, directory.companion
	local injectedProfiles, injectedCharacters = session.injectedProfiles, session.injectedCharacters
	local touchedProfiles = {}

	-- Profiles: add missing ones; when both exist, keep the one seen last.
	for profileID, archived in pairs(archive.profiles) do
		if type(archived) == "table" and HasCharacteristics(archived) then
			local current = profiles[profileID]
			if current == nil then
				profiles[profileID] = archived
				injectedProfiles[profileID] = true
				touchedProfiles[profileID] = true
			elseif current ~= archived and ProfileTime(archived) > ProfileTime(current) then
				profiles[profileID] = archived -- TRP3's copy was older; it stays TRP3's own entry
				touchedProfiles[profileID] = true
			end
		end
	end

	-- Characters: add missing ones; when both exist, keep the binding to the profile seen last.
	local rebound = {}
	for characterID, archived in pairs(archive.character) do
		local profileID = type(archived) == "table" and archived.profileID
		if profileID and profiles[profileID] and not blockList[characterID] then
			local current = characters[characterID]
			if current == nil then
				characters[characterID] = archived
				injectedCharacters[characterID] = true
				rebound[characterID] = profileID
			elseif current ~= archived and current.profileID ~= profileID then
				local currentProfile = current.profileID and profiles[current.profileID]
				if not currentProfile or ProfileTime(profiles[profileID]) > ProfileTime(currentProfile) then
					if currentProfile and type(currentProfile.link) == "table" then
						currentProfile.link[characterID] = nil
					end
					characters[characterID] = archived
					rebound[characterID] = profileID
				end
			end
		end
	end

	-- TRP3 keeps profile.link and character.profileID in step; do the same for what was added.
	for profileID in pairs(touchedProfiles) do
		local profile = profiles[profileID]
		if type(profile.link) ~= "table" then profile.link = {} end
		for characterID in pairs(profile.link) do
			local character = characters[characterID]
			if not character or character.profileID ~= profileID then
				profile.link[characterID] = nil
			end
		end
	end
	for characterID, character in pairs(characters) do
		local profileID = character.profileID
		if profileID and (rebound[characterID] or touchedProfiles[profileID]) then
			local profile = profiles[profileID]
			if profile then
				if type(profile.link) ~= "table" then profile.link = {} end
				profile.link[characterID] = 1
			end
		end
	end

	-- Companions: add missing ones.
	for companionID, archived in pairs(archive.companion) do
		if type(archived) == "table" and companions[companionID] == nil then
			companions[companionID] = archived
			session.injectedCompanions[companionID] = true
		end
	end

	-- What TRP3's directory holds now; anything missing at logout was deleted during the session.
	session.knownProfiles = KeySet(profiles)
	session.knownCharacters = KeySet(characters)
	session.knownCompanions = KeySet(companions)
	return session
end

---------------------------------------------------------------------------
-- Logout: update the archive, then hand TRP3 back its own directory
---------------------------------------------------------------------------

--- Brings the archive up to date with TRP3's directory.
function Archive.Update(archive, directory, session)
	local profiles, characters, companions = directory.profiles, directory.character, directory.companion
	local archivedProfiles, archivedCharacters, archivedCompanions = archive.profiles, archive.character, archive.companion

	-- Deleted in TRP3 during the session (by the player, or by TRP3 when a character changed profile).
	for profileID in pairs(session.knownProfiles) do
		if profiles[profileID] == nil then archivedProfiles[profileID] = nil end
	end
	for characterID in pairs(session.knownCharacters) do
		if characters[characterID] == nil then archivedCharacters[characterID] = nil end
	end
	for companionID in pairs(session.knownCompanions) do
		if companions[companionID] == nil then archivedCompanions[companionID] = nil end
	end

	-- Profiles: keep whichever was seen last.
	for profileID, profile in pairs(profiles) do
		local archived = archivedProfiles[profileID]
		if archived ~= profile and (archived == nil or ProfileTime(profile) >= ProfileTime(archived)) then
			archivedProfiles[profileID] = profile
		end
	end

	-- Characters follow their profile: keep the binding whose profile was seen last.
	-- The archive often holds the very same table as TRP3, which TRP3 edits in place (for example when a
	-- profile is deleted, its characters lose their profileID), so decide on content, not identity.
	for characterID, character in pairs(characters) do
		local archived = archivedCharacters[characterID]
		if not character.profileID then
			-- TRP3 only keeps characters without a profile for its ignore list; the archive has no use for them.
			archivedCharacters[characterID] = nil
		elseif archived ~= character and (archived == nil or not archived.profileID or archived.profileID == character.profileID
			or ProfileTime(archivedProfiles[character.profileID]) >= ProfileTime(archivedProfiles[archived.profileID])) then
			archivedCharacters[characterID] = character
		end
	end

	-- Companions have no date; TRP3's current version is the latest.
	for companionID, companion in pairs(companions) do
		archivedCompanions[companionID] = companion
	end
end

--- Takes the entries that were only added for display back out of TRP3's directory.
--- Kept: TRP3's own entries, anything seen or changed this session, and protected profiles.
function Archive.Trim(directory, session, protected)
	local profiles, characters, companions = directory.profiles, directory.character, directory.companion
	local injectedProfiles, importedProfiles = session.injectedProfiles, session.importedProfiles
	local injectedCharacters, injectedCompanions = session.injectedCharacters, session.injectedCompanions
	local sessionStart = session.sessionStart
	protected = protected or {}

	local keep = {}
	for profileID, profile in pairs(profiles) do
		if not injectedProfiles[profileID] or protected[profileID]
			or (not importedProfiles[profileID] and ProfileTime(profile) >= sessionStart) then
			keep[profileID] = true
		end
	end
	-- A profile that one of TRP3's own characters points to stays with that character.
	for characterID, character in pairs(characters) do
		local profileID = character.profileID
		if profileID and not injectedCharacters[characterID] and profiles[profileID] then
			keep[profileID] = true
		end
	end

	local removed = { profiles = 0, characters = 0, companions = 0 }

	-- Characters stay or go together with their profile.
	for characterID, character in pairs(characters) do
		local stays
		if character.profileID and profiles[character.profileID] then
			stays = keep[character.profileID]
		else
			stays = not injectedCharacters[characterID]
		end
		if not stays then
			characters[characterID] = nil
			removed.characters = removed.characters + 1
		end
	end
	for profileID in pairs(profiles) do
		if not keep[profileID] then
			profiles[profileID] = nil
			removed.profiles = removed.profiles + 1
		end
	end
	-- Added companions stay only while one of their owners is still in TRP3's directory.
	for companionID, companion in pairs(companions) do
		if injectedCompanions[companionID] then
			local stays = false
			if type(companion.links) == "table" then
				for companionFullID in pairs(companion.links) do
					local owner = Archive.CompanionOwner(companionFullID)
					if owner and characters[owner] then
						stays = true
						break
					end
				end
			end
			if not stays then
				companions[companionID] = nil
				removed.companions = removed.companions + 1
			end
		end
	end
	return removed
end
