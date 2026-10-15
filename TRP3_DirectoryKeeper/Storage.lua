-- TRP3 Directory Keeper
-- Reading and writing the archive file (TRP3DK_Archive, the saved variable of the data-only addon
-- TRP3_DirectoryKeeper_Archive).
--
-- One saved-variables file allows at most 262,143 unique Lua constants, so the archive is not
-- stored as plain tables. Each section (profiles, character, companion) is split into numbered
-- blocks; a block is one "return{...}" string, which counts as a single constant however much it
-- holds. An entry always goes into the block given by a hash of its key, so blocks stay stable.
--
-- At login every block is read back into tables, and a fingerprint of every entry is noted. At
-- logout only the blocks holding new, deleted or changed entries are written again; all other
-- blocks are saved exactly as they were read. Every FULL_WRITE_EVERY logouts, and whenever the
-- number of blocks no longer suits the archive's size, all blocks are rewritten, which also picks
-- up the rare change no fingerprint covers (such as an About page's read flag).

local _, ns = ...

local Serializer = ns.Serializer
local pairs, ipairs, next, type, tostring, pcall = pairs, ipairs, next, type, tostring, pcall
local loadstring, setfenv = loadstring, setfenv
local byte, concat = string.byte, table.concat

local Storage = {}
ns.Storage = Storage

Storage.FULL_WRITE_EVERY = 20
-- Entries per block aimed for when the number of blocks is chosen (about 200 KB per block).
local ENTRIES_PER_BLOCK = { profiles = 64, character = 256, companion = 64 }
local MIN_BLOCKS = 8
local EMPTY_BLOCK = "return{}"

local function NewDirectory()
	return { profiles = {}, character = {}, companion = {} }
end

--- Stable block number of a key (djb2 string hash).
function Storage.BlockOf(key, blockCount)
	key = tostring(key)
	local hash = 5381
	for i = 1, #key do
		hash = (hash * 33 + byte(key, i)) % 4294967296
	end
	return hash % blockCount + 1
end

function Storage.BlockCountFor(section, entryCount)
	local count = MIN_BLOCKS
	while count * ENTRIES_PER_BLOCK[section] < entryCount do
		count = count * 2
	end
	return count
end

---------------------------------------------------------------------------
-- Fingerprints: cheap summaries that change whenever TRP3 updates an entry
---------------------------------------------------------------------------

local function CountKeys(t)
	local n = 0
	if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
	return n
end

local function Version(t)
	return type(t) == "table" and tostring(t.v) or "-"
end

local FINGERPRINT = {
	profiles = function(profile)
		local about = type(profile.about) == "table" and profile.about or nil
		return concat({
			tostring(profile.time), CountKeys(profile.link), Version(profile.characteristics), Version(about),
			Version(profile.misc), Version(profile.character), tostring(about and about.read), CountKeys(profile.mspver),
		}, ":")
	end,
	character = function(character)
		return concat({
			tostring(character.profileID), tostring(character.guild), tostring(character.client),
			tostring(character.clientVersion), tostring(character.extendedVersion), tostring(character.roleplayExperience),
		}, ":")
	end,
	companion = function(companion)
		local data = type(companion.data) == "table" and companion.data or nil
		return concat({
			Version(data), Version(companion.PE), CountKeys(companion.links), tostring(data and data.read),
		}, ":")
	end,
}

--- Notes every entry and its fingerprint, to find what changed at logout.
function Storage.Snapshot(archive)
	local snapshot = { entries = {}, fingerprints = {} }
	for _, section in ipairs(ns.SECTIONS) do
		local entries, fingerprints = {}, {}
		local fingerprint = FINGERPRINT[section]
		for key, entry in pairs(archive[section]) do
			entries[key] = entry
			fingerprints[key] = fingerprint(entry)
		end
		snapshot.entries[section] = entries
		snapshot.fingerprints[section] = fingerprints
	end
	return snapshot
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------

-- Blocks are written by this addon from the player's own directory, so they are read with
-- loadstring (fast) in an empty environment. Received exports never go through this path.
local function ReadBlock(text)
	if type(text) ~= "string" then return nil end
	local fn = loadstring(text, "TRP3DK_Archive block")
	if not fn then return nil end
	setfenv(fn, {})
	local ok, result = pcall(fn)
	if ok and type(result) == "table" then return result end
	return nil
end

--- Reads the saved archive. Returns the archive (three tables of entries) and the storage record
--- needed to write it back. Unreadable blocks are kept untouched in the record and saved again.
function Storage.Load(saved)
	local archive = NewDirectory()
	local store = { sections = {}, unreadable = {}, unreadableCount = 0, forceFull = false }

	local usable = type(saved) == "table" and saved.format == ns.ARCHIVE_FORMAT
	store.meta = usable and {
		schema = saved.schema, savedAt = saved.savedAt, addonVersion = saved.addonVersion,
		writesSinceFull = tonumber(saved.writesSinceFull) or 0,
	} or { writesSinceFull = 0 }
	if type(saved) == "table" and next(saved) ~= nil and not usable then
		store.unknownFormat = true -- a newer version wrote this file; leave it alone
		return archive, store
	end

	for _, section in ipairs(ns.SECTIONS) do
		local list = usable and type(saved[section]) == "table" and saved[section] or {}
		local record = { count = #list, texts = {}, keys = {}, blockOf = {} }
		local target = archive[section]
		for i = 1, record.count do
			local text = list[i]
			local data = ReadBlock(text)
			local keys = {}
			if data then
				record.texts[i] = text
				for key, entry in pairs(data) do
					if type(entry) == "table" then
						if target[key] ~= nil then store.forceFull = true end -- duplicate: rewrite everything once
						target[key] = entry
						keys[key] = true
						record.blockOf[key] = i
					end
				end
			else
				record.texts[i] = EMPTY_BLOCK
				local kept = store.unreadable[section] or {}
				kept[#kept + 1] = text
				store.unreadable[section] = kept
				store.unreadableCount = store.unreadableCount + 1
			end
			record.keys[i] = keys
		end
		store.sections[section] = record
	end

	-- Blocks that could not be read in an earlier session stay in the file until someone looks at them.
	if usable and type(saved.unreadable) == "table" then
		for section, list in pairs(saved.unreadable) do
			if type(list) == "table" then
				local kept = store.unreadable[section] or {}
				for _, text in ipairs(list) do kept[#kept + 1] = text end
				store.unreadable[section] = kept
				store.unreadableCount = store.unreadableCount + #list
			end
		end
	end
	return archive, store
end

---------------------------------------------------------------------------
-- Writing
---------------------------------------------------------------------------

local function WriteAllBlocks(entries, blockCount)
	local blocks = {}
	for i = 1, blockCount do blocks[i] = {} end
	for key, entry in pairs(entries) do
		blocks[Storage.BlockOf(key, blockCount)][key] = entry
	end
	local texts = {}
	for i = 1, blockCount do
		texts[i] = next(blocks[i]) and Serializer.SerializeBlock(blocks[i]) or EMPTY_BLOCK
	end
	return texts
end

--- Writes only the blocks of a section that hold new, deleted or changed entries.
local function WriteChangedBlocks(entries, record, snapshotEntries, snapshotFingerprints, fingerprint)
	local count, keys, blockOf = record.count, record.keys, record.blockOf
	local changed = {}

	-- Compare fingerprints, not tables: with TRP3's purge off, the archive takes over TRP3's own copy
	-- of every entry at logout, which is a different table with the same contents.
	for key, entry in pairs(entries) do
		if snapshotFingerprints[key] ~= fingerprint(entry) then
			local block = blockOf[key]
			if not block then
				block = Storage.BlockOf(key, count)
				blockOf[key] = block
				keys[block][key] = true
			end
			changed[block] = true
		end
	end
	for key in pairs(snapshotEntries) do
		if entries[key] == nil then
			local block = blockOf[key]
			if block then
				changed[block] = true
				keys[block][key] = nil
				blockOf[key] = nil
			end
		end
	end

	local texts, rewritten = {}, 0
	for i = 1, count do
		if changed[i] then
			local block = {}
			for key in pairs(keys[i]) do block[key] = entries[key] end
			texts[i] = next(block) and Serializer.SerializeBlock(block) or EMPTY_BLOCK
			rewritten = rewritten + 1
		else
			texts[i] = record.texts[i]
		end
	end
	return texts, rewritten
end

--- Builds the saved archive. info: { schema, now, addonVersion }. Returns the table to save as
--- TRP3DK_Archive and a summary of what was written.
function Storage.Save(archive, store, snapshot, info)
	local writes = store.meta.writesSinceFull + 1
	local fullEverything = store.forceFull or writes >= Storage.FULL_WRITE_EVERY
	local saved = {
		format = ns.ARCHIVE_FORMAT,
		addonVersion = info.addonVersion,
		schema = info.schema,
		savedAt = info.now,
	}
	local summary = { full = {}, rewritten = 0, blocks = 0, counts = {} }
	local allFull = true

	for _, section in ipairs(ns.SECTIONS) do
		local entries = archive[section]
		local entryCount = CountKeys(entries)
		local record = store.sections[section]
		local wanted = Storage.BlockCountFor(section, entryCount)
		local count = record and record.count or 0
		local texts
		if fullEverything or count == 0 or count * 2 < wanted or count > wanted * 2 then
			texts = WriteAllBlocks(entries, wanted)
			summary.rewritten = summary.rewritten + wanted
			summary.full[section] = true
		else
			local rewritten
			texts, rewritten = WriteChangedBlocks(entries, record, snapshot.entries[section],
				snapshot.fingerprints[section], FINGERPRINT[section])
			summary.rewritten = summary.rewritten + rewritten
			allFull = false
		end
		saved[section] = texts
		summary.blocks = summary.blocks + #texts
		summary.counts[section] = entryCount
	end

	saved.writesSinceFull = allFull and 0 or writes
	if next(store.unreadable) then saved.unreadable = store.unreadable end
	saved.counts = { profiles = summary.counts.profiles, characters = summary.counts.character, companions = summary.counts.companion }
	return saved, summary
end
