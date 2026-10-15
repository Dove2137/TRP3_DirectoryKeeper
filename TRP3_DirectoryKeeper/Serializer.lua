-- TRP3 Directory Keeper
-- Turns directory entries into plain strings and back.
--
-- Export files store the directory as a few hundred "chunk" strings of the form
--   return{[key]=value,[key]=value,...}
-- Each chunk is a single string constant in the saved-variables file, so an export of any size
-- stays far below Lua's constant limit.
--
-- Reading a chunk never runs it as code: Serializer.Parse is a small parser that only accepts
-- exactly what Serializer writes (strings, numbers, booleans and nested tables). A damaged or
-- malicious chunk is rejected with an error instead of being executed.

local _, ns = ...

local type, pairs, tostring, tonumber = type, pairs, tostring, tonumber
local format, concat = string.format, table.concat
local find, sub, byte, char, gsub = string.find, string.sub, string.byte, string.char, string.gsub
local HUGE = math.huge

local Serializer = {}
ns.Serializer = Serializer

Serializer.CHUNK_BYTES = 256 * 1024
Serializer.MAX_DEPTH = 32

-- Midnight (12.x) secret values cannot be saved (TRP3 can store game values such as a guild name
-- read during a session); skip them one by one so a single secret never spoils a whole chunk.
local issecretvalue = issecretvalue

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------

local function SerializeNumber(n)
	if n ~= n then return "(0/0)" end
	if n == HUGE then return "(1/0)" end
	if n == -HUGE then return "(-1/0)" end
	return format("%.17g", n)
end

local function WriteKey(key, buffer, n)
	if issecretvalue(key) then return nil end
	local keyType = type(key)
	if keyType == "string" then
		buffer[n + 1] = "["; buffer[n + 2] = format("%q", key); buffer[n + 3] = "]="
		return n + 3
	elseif keyType == "number" then
		if key ~= key then return nil end
		buffer[n + 1] = "["; buffer[n + 2] = SerializeNumber(key); buffer[n + 3] = "]="
		return n + 3
	elseif keyType == "boolean" then
		buffer[n + 1] = key and "[true]=" or "[false]="
		return n + 1
	end
	return nil
end

local WriteValue

function WriteValue(value, buffer, n, depth)
	local valueType = type(value)
	if issecretvalue(value) then
		n = n + 1; buffer[n] = "nil"
	elseif valueType == "string" then
		n = n + 1; buffer[n] = format("%q", value)
	elseif valueType == "number" then
		n = n + 1; buffer[n] = SerializeNumber(value)
	elseif valueType == "boolean" then
		n = n + 1; buffer[n] = value and "true" or "false"
	elseif valueType == "table" and depth < Serializer.MAX_DEPTH then
		n = n + 1; buffer[n] = "{"
		for key, sub in pairs(value) do
			local subType = type(sub)
			if subType == "string" or subType == "number" or subType == "boolean" or subType == "table" then
				local afterKey = WriteKey(key, buffer, n)
				if afterKey then
					n = WriteValue(sub, buffer, afterKey, depth + 1)
					n = n + 1; buffer[n] = ","
				end
			end
		end
		n = n + 1; buffer[n] = "}"
	else
		n = n + 1; buffer[n] = "nil"
	end
	return n
end

--- Serializes one "[key]=value," entry, or returns nil when the key cannot be saved.
function Serializer.SerializeEntry(key, value)
	local buffer = {}
	local n = WriteKey(key, buffer, 0)
	if not n then return nil end
	n = WriteValue(value, buffer, n, 1)
	n = n + 1; buffer[n] = ","
	return concat(buffer, "", 1, n)
end

--- Serializes a whole table of entries into one "return{...}" block.
function Serializer.SerializeBlock(entries)
	local parts = { "return{" }
	for key, value in pairs(entries) do
		local entry = Serializer.SerializeEntry(key, value)
		if entry then parts[#parts + 1] = entry end
	end
	parts[#parts + 1] = "}"
	return concat(parts)
end

--- Collects entries into chunk strings of about CHUNK_BYTES each.
function Serializer.NewChunker()
	local chunker = { chunks = {}, parts = {}, size = 0, entries = 0 }

	function chunker:Add(key, value)
		local entry = Serializer.SerializeEntry(key, value)
		if not entry then return false end
		local parts = self.parts
		parts[#parts + 1] = entry
		self.size = self.size + #entry
		self.entries = self.entries + 1
		if self.size >= Serializer.CHUNK_BYTES then
			self:Flush()
		end
		return true
	end

	function chunker:Flush()
		if #self.parts > 0 then
			self.chunks[#self.chunks + 1] = "return{" .. concat(self.parts) .. "}"
			self.parts, self.size = {}, 0
		end
	end

	function chunker:Finish()
		self:Flush()
		return self.chunks
	end

	return chunker
end

---------------------------------------------------------------------------
-- Reading (data only, never executed)
---------------------------------------------------------------------------

-- string.format("%q") in Lua 5.1 writes \" \\ \r \000 and a backslash followed by a real newline.
local ESCAPES = {
	['"'] = '"', ["\\"] = "\\", ["\n"] = "\n", ["'"] = "'",
	n = "\n", r = "\r", t = "\t", a = "\a", b = "\b", f = "\f", v = "\v",
}

local function Unescape(first, digits)
	if find(first, "^%d$") then
		local code = tonumber(first .. digits)
		if code > 255 then error("invalid escape sequence", 0) end
		return char(code)
	end
	local replacement = ESCAPES[first]
	if not replacement then error("invalid escape sequence", 0) end
	return replacement .. digits
end

local SPECIAL_NUMBERS = { ["(0/0)"] = 0 / 0, ["(1/0)"] = HUGE, ["(-1/0)"] = -HUGE }
local NIL = {}

--- Parses one chunk written by Serializer and returns its table. Raises an error for anything else.
function Serializer.Parse(text)
	if type(text) ~= "string" or sub(text, 1, 7) ~= "return{" then
		error("not a Directory Keeper data block", 0)
	end
	local pos = 7 -- at the opening brace

	local function Fail(message)
		error(format("damaged data block (%s at byte %d)", message, pos), 0)
	end

	local function ReadString()
		local start = pos + 1
		local scan = start
		local escaped = false
		while true do
			local at = find(text, '["\\]', scan)
			if not at then Fail("unterminated text") end
			if byte(text, at) == 34 then -- closing quote
				local raw = sub(text, start, at - 1)
				pos = at + 1
				if escaped then
					raw = gsub(raw, "\\(.)(%d?%d?)", Unescape)
				end
				return raw
			end
			escaped = true
			scan = at + 2
		end
	end

	local function ReadNumber()
		local s, e = find(text, "^%-?%d[%d%.]*[eE]?[%+%-]?%d*", pos)
		if s then
			local number = tonumber(sub(text, s, e))
			if number then
				pos = e + 1
				return number
			end
		end
		for literal, value in pairs(SPECIAL_NUMBERS) do
			if sub(text, pos, pos + #literal - 1) == literal then
				pos = pos + #literal
				return value
			end
		end
		Fail("unexpected character")
	end

	local ReadTable

	local function ReadValue(depth)
		local b = byte(text, pos)
		if b == 34 then
			return ReadString()
		elseif b == 123 then
			return ReadTable(depth + 1)
		elseif b == 116 and sub(text, pos, pos + 3) == "true" then
			pos = pos + 4; return true
		elseif b == 102 and sub(text, pos, pos + 4) == "false" then
			pos = pos + 5; return false
		elseif b == 110 and sub(text, pos, pos + 2) == "nil" then
			pos = pos + 3; return NIL
		end
		return ReadNumber()
	end

	local function ReadKey()
		local b = byte(text, pos)
		if b == 34 then
			return ReadString()
		elseif b == 116 and sub(text, pos, pos + 3) == "true" then
			pos = pos + 4; return true
		elseif b == 102 and sub(text, pos, pos + 4) == "false" then
			pos = pos + 5; return false
		end
		local key = ReadNumber()
		if key ~= key then Fail("invalid key") end
		return key
	end

	function ReadTable(depth)
		if depth > Serializer.MAX_DEPTH then Fail("nested too deeply") end
		pos = pos + 1 -- skip {
		local result = {}
		while true do
			local b = byte(text, pos)
			if b == 125 then -- }
				pos = pos + 1
				return result
			elseif b ~= 91 then -- [
				Fail("expected an entry")
			end
			pos = pos + 1
			local key = ReadKey()
			if sub(text, pos, pos + 1) ~= "]=" then Fail("expected ]=") end
			pos = pos + 2
			local value = ReadValue(depth)
			if byte(text, pos) ~= 44 then Fail("expected a comma") end -- ,
			pos = pos + 1
			if value ~= NIL then
				result[key] = value
			end
		end
	end

	local result = ReadTable(0)
	if pos ~= #text + 1 then Fail("unexpected data after the end") end
	return result
end
