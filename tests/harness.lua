-- Test harness: runs the addon under plain Lua 5.1 with minimal stand-ins for the WoW API.
--
-- Each simulated game session gets a fresh global environment. Saved variables are written the way
-- the game writes them and read back with Lua's own loader, so a file that would hit the constant
-- limit in game fails here too ("constant table overflow").

local H = {}

local ADDON_NAME = "TRP3_DirectoryKeeper"
local ADDON_FILES = { "Init.lua", "Serializer.lua", "Storage.lua", "Archive.lua", "Exchange.lua", "UI.lua", "Main.lua" }

H.quiet = false

local function Log(env, message)
	message = tostring(message):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n")
	env.__chat[#env.__chat + 1] = message
	if not H.quiet then print("    [chat] " .. message) end
end

local function NewFrame(env, name)
	local frame = { scripts = {}, events = {}, scale = 1, points = {} }
	function frame:RegisterEvent(event) self.events[event] = true end
	function frame:UnregisterEvent(event) self.events[event] = nil end
	function frame:SetScript(script, fn) self.scripts[script] = fn end
	function frame:GetScale() return self.scale end
	function frame:SetScale(scale) self.scale = scale end
	function frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
	frame.Icon = { SetTexture = function(icon, texture) icon.texture = texture end }
	env.__frames[#env.__frames + 1] = frame
	if name then env[name] = frame end
	return frame
end

--- A fresh global environment with the WoW functions the addon uses.
function H.NewEnvironment()
	local env = { __frames = {}, __chat = {}, __popups = {}, __loaded = {} }
	for key, value in pairs(_G) do env[key] = value end
	env._G = env

	env.CreateFrame = function(_, name) return NewFrame(env, name) end
	env.issecretvalue = function() return false end
	env.debugprofilestop = function() return os.clock() * 1000 end
	env.time = function() return env.__now or os.time() end
	env.date = os.date
	env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
	env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) Log(env, message) end }
	env.ACCEPT, env.CANCEL, env.OKAY = "Accept", "Cancel", "Okay"
	env.StaticPopupDialogs = {}
	env.StaticPopup_Show = function(which, text, _, data)
		env.__popups[#env.__popups + 1] = { which = which, text = text, data = data }
		Log(env, "[popup " .. which .. "] " .. tostring(text))
	end
	env.ReloadUI = function() env.__reloadRequested = true end
	env.SlashCmdList = {}
	env.C_AddOns = {
		GetAddOnMetadata = function(addon, field) return field == "Version" and (addon == "totalRP3" and "3.5.1" or "1.0.0") or nil end,
		IsAddOnLoaded = function(addon) return env.__loaded[addon] == true end,
		LoadAddOn = function(addon)
			env.__loaded[addon] = true
			if env.__onLoadAddOn then env.__onLoadAddOn(addon) end
			return true
		end,
	}
	env.TRP3_API = {
		register = { sanitizeProfile = function() return false end },
		ui = { tooltip = { setTooltipForSameFrame = function(frame, _, _, _, title) frame.tooltipTitle = title end } },
	}
	local panel = NewFrame(env, "TRP3_RegisterListCharactFilter")
	local search = NewFrame(env, "TRP3_RegisterListCharactFilterButton")
	search.scale = 0.8
	return env
end

--- Loads the addon's files into the environment, like the game does for TRP3_DirectoryKeeper.
function H.LoadAddon(env, addonDir)
	local ns = {}
	for _, file in ipairs(ADDON_FILES) do
		local chunk = assert(loadfile(addonDir .. "/" .. file))
		setfenv(chunk, env)
		chunk(ADDON_NAME, ns)
	end
	env.__ns = ns
	return ns
end

function H.FireEvent(env, event, ...)
	for _, frame in ipairs(env.__frames) do
		if frame.events[event] and frame.scripts.OnEvent then
			frame.scripts.OnEvent(frame, event, ...)
		end
	end
end

--- Runs OnUpdate scripts (background jobs) until none are left.
function H.RunUpdates(env)
	local frames = 0
	repeat
		local any = false
		for _, frame in ipairs(env.__frames) do
			if frame.scripts.OnUpdate then
				any = true
				frame.scripts.OnUpdate(frame, 0.016)
				frames = frames + 1
			end
		end
	until not any
	return frames
end

function H.Slash(env, text)
	env.SlashCmdList.TRP3DIRECTORYKEEPER(text)
end

--- Accepts the last popup of the given kind.
function H.AcceptPopup(env, which)
	for i = #env.__popups, 1, -1 do
		local popup = env.__popups[i]
		if popup.which == which then
			local dialog = env.StaticPopupDialogs[which]
			if dialog.OnAccept then dialog.OnAccept(nil, popup.data) end
			return popup
		end
	end
	error("no popup " .. which)
end

---------------------------------------------------------------------------
-- Saved variables, written like the game writes them
---------------------------------------------------------------------------

local function WriteValue(out, value)
	local valueType = type(value)
	if valueType == "string" then
		out[#out + 1] = string.format("%q", value)
	elseif valueType == "number" then
		out[#out + 1] = string.format("%.17g", value)
	elseif valueType == "boolean" then
		out[#out + 1] = tostring(value)
	elseif valueType == "table" then
		out[#out + 1] = "{\n"
		for key, sub in pairs(value) do
			local subType = type(sub)
			if subType == "string" or subType == "number" or subType == "boolean" or subType == "table" then
				if type(key) == "string" then
					out[#out + 1] = "[" .. string.format("%q", key) .. "] = "
				else
					out[#out + 1] = "[" .. tostring(key) .. "] = "
				end
				WriteValue(out, sub)
				out[#out + 1] = ",\n"
			end
		end
		out[#out + 1] = "}"
	else
		out[#out + 1] = "nil"
	end
end

function H.WriteSavedVariables(path, env, names)
	local out = {}
	for _, name in ipairs(names) do
		out[#out + 1] = name .. " = "
		WriteValue(out, env[name])
		out[#out + 1] = "\n"
	end
	local file = assert(io.open(path, "wb"))
	file:write(table.concat(out))
	file:close()
end

--- Reads a saved-variables file into env. Returns false, error when Lua cannot load it.
function H.ReadSavedVariables(path, env)
	local chunk, err = loadfile(path)
	if not chunk then return false, err end
	setfenv(chunk, env)
	chunk()
	return true
end

function H.FileSize(path)
	local file = io.open(path, "rb")
	if not file then return 0 end
	local size = file:seek("end")
	file:close()
	return size
end

function H.Count(t)
	local n = 0
	if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
	return n
end

local failures = 0
function H.Check(condition, message)
	if condition then
		print("  ok    " .. message)
	else
		failures = failures + 1
		print("  FAIL  " .. message)
	end
end

function H.Failures() return failures end

return H
