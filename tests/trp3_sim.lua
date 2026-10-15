-- What Total RP 3 (3.4.3 to 3.5.1) does to its directory at login, reproduced from
-- Modules/Register/Characters/RegisterMain.lua (cleanupPlayerRelations, cleanupProfiles,
-- cleanupCharacters, cleanupCompanions). Used by the session simulation to check that the
-- Directory Keeper and TRP3's own cleanup work together.
--
-- Based on Total RP 3, Copyright The Total RP 3 Authors, licensed under the Apache License 2.0
-- (https://github.com/Total-RP/Total-RP-3). Adapted: reduced to the directory cleanup and changed
-- to work on a test environment instead of the game.

local Sim = {}

local function DeleteProfile(profiles, characters, profileID)
	local profile = profiles[profileID]
	if profile.link then
		for characterID in pairs(profile.link) do
			if characters[characterID] and characters[characterID].profileID == profileID then
				characters[characterID].profileID = nil
			end
		end
	end
	profiles[profileID] = nil
end
Sim.DeleteProfile = DeleteProfile

--- Runs TRP3's login cleanup on env.TRP3_Register. purgeSeconds: number, or false for "never".
function Sim.Login(env, purgeSeconds, now)
	local register = env.TRP3_Register
	if not register then register = {}; env.TRP3_Register = register end
	register.character = register.character or {}
	register.profiles = register.profiles or {}
	register.companion = register.companion or {}
	register.blockList = register.blockList or {}
	local profiles, characters, companions, blockList = register.profiles, register.character, register.companion, register.blockList
	local ownProfiles = env.TRP3_Profiles or {}

	-- cleanupPlayerRelations
	for _, myProfile in pairs(ownProfiles) do
		for profileID in pairs(myProfile.relation or {}) do
			if not profiles[profileID] then myProfile.relation[profileID] = nil end
		end
	end

	-- cleanupProfiles
	for _, profile in pairs(profiles) do
		if not profile.link then profile.link = {} end
	end
	for profileID, profile in pairs(profiles) do
		if not profile.characteristics or next(profile.characteristics) == nil then DeleteProfile(profiles, characters, profileID) end
	end
	for profileID, profile in pairs(profiles) do
		if profile.msp and next(profile.link) == nil then DeleteProfile(profiles, characters, profileID) end
	end
	if type(purgeSeconds) == "number" then
		local protected = {}
		for _, profile in pairs(ownProfiles) do
			for profileID in pairs(profile.relation or {}) do protected[profileID] = true end
			for profileID in pairs(profile.notes or {}) do protected[profileID] = true end
		end
		local toPurge = {}
		for profileID, profile in pairs(profiles) do
			if not protected[profileID] and (not profile.time or now - profile.time > purgeSeconds) then
				toPurge[#toPurge + 1] = profileID
			end
		end
		for _, profileID in ipairs(toPurge) do DeleteProfile(profiles, characters, profileID) end
	end

	-- cleanupCharacters
	for characterID, character in pairs(characters) do
		local profileID = character.profileID
		if profileID and (not profiles[profileID] or not profiles[profileID].link or not profiles[profileID].link[characterID]) then
			character.profileID = nil
		end
	end
	for characterID, character in pairs(characters) do
		if not character.profileID and not blockList[characterID] then
			characters[characterID] = nil
		end
	end

	-- cleanupCompanions
	for companionID, companion in pairs(companions) do
		for companionFullID in pairs(companion.links or {}) do
			local ownerID = companionFullID:match("^([^_]+)_") or companionFullID
			local character = characters[ownerID]
			if not character or not character.profileID or not profiles[character.profileID] then
				companion.links[companionFullID] = nil
			end
		end
		if next(companion.links or {}) == nil then companions[companionID] = nil end
	end

	env.TRP3_Flyway = env.TRP3_Flyway or {}
	env.TRP3_Flyway.currentBuild = 25
end

return Sim
