-- TRP3 Directory Keeper
-- Shared constants and small helpers used by every other file.

local ADDON_NAME, ns = ...

ns.NAME = ADDON_NAME
ns.VERSION = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version") or "dev"

-- The parts of TRP3_Register that the archive keeps. The ignore list (blockList) is never archived or exported.
ns.SECTIONS = { "profiles", "character", "companion" }

-- Archive storage: the saved variable of the data-only addon TRP3_DirectoryKeeper_Archive.
ns.ARCHIVE_VARIABLE = "TRP3DK_Archive"
ns.ARCHIVE_FORMAT = 1

-- Exchange slot: a load-on-demand addon whose saved-variables file is the file people send each other.
ns.EXCHANGE_ADDON = "TRP3_DirectoryKeeper_Exchange"
ns.EXCHANGE_VARIABLE = "TRP3DK_Exchange"
ns.EXCHANGE_KIND = "TRP3 Directory Keeper export"
ns.EXCHANGE_FORMAT = 1

-- WoW loads a saved-variables file as one Lua 5.1 chunk, which allows at most 262,143 unique
-- constants. A TRP3 directory profile needs about 16.5 of them on average (measured on a
-- 15,500-profile directory), which is what the near-limit warning is based on.
ns.CONSTANT_LIMIT = 262143
ns.CONSTANTS_PER_PROFILE = 16.5
ns.WARNING_RATIO = 0.9

-- Runtime state shown by /tdk.
ns.status = {}

local CHAT_PREFIX = "|cff66ccffTRP3 Directory Keeper:|r "

function ns.Print(message, ...)
	if select("#", ...) > 0 then
		message = message:format(...)
	end
	if DEFAULT_CHAT_FRAME then
		DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. message)
	end
end

function ns.CountKeys(t)
	local count = 0
	if type(t) == "table" then
		for _ in pairs(t) do count = count + 1 end
	end
	return count
end

function ns.KeySet(t)
	local set = {}
	if type(t) == "table" then
		for key in pairs(t) do set[key] = true end
	end
	return set
end

--- Last time this profile was seen (TRP3 stores it in profile.time), or 0 when unknown.
function ns.ProfileTime(profile)
	if type(profile) == "table" and type(profile.time) == "number" then
		return profile.time
	end
	return 0
end

--- Estimated share of the saved-variables constant limit used by a directory of this many profiles.
function ns.EstimateUsage(profileCount)
	return profileCount * ns.CONSTANTS_PER_PROFILE / ns.CONSTANT_LIMIT
end

function ns.FormatDate(timestamp)
	if type(timestamp) ~= "number" then return "unknown date" end
	return date("%Y-%m-%d %H:%M", timestamp)
end
