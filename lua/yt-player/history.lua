---@mod yt-player.history Persistent play history
local M = {}

local utils = require("yt-player.utils")

local MAX_ENTRIES = 100

local function history_path()
	return vim.fn.stdpath("data") .. "/yt-player-history.json"
end

--- Read history from disk
---@return table[]
function M.get()
	return utils.read_json_store(history_path(), "history")
end

--- Write history to disk
---@param data table[]
local function save(data)
	utils.atomic_write_json(history_path(), data)
end

--- Add a track to history (newest first, deduplicated by URL)
---@param entry table {title, url, duration?, channel?}
function M.add(entry)
	if not entry or not entry.url or entry.url == "" then
		return
	end

	local history = M.get()

	-- Remove duplicate if exists
	local filtered = {}
	for _, item in ipairs(history) do
		if item.url ~= entry.url then
			table.insert(filtered, item)
		end
	end

	-- Prepend new entry
	table.insert(filtered, 1, {
		title = entry.title or "Unknown",
		url = entry.url,
		duration = entry.duration or 0,
		channel = entry.channel or "",
		timestamp = os.time(),
	})

	-- Cap at max
	while #filtered > MAX_ENTRIES do
		table.remove(filtered)
	end

	save(filtered)
end

--- Update duration for an existing history entry if it was 0
---@param url string
---@param duration number
function M.update_duration(url, duration)
	if not url or url == "" or not duration or duration <= 0 then
		return
	end
	local history = M.get()
	local updated = false
	for _, item in ipairs(history) do
		if item.url == url and (not item.duration or item.duration == 0) then
			item.duration = duration
			updated = true
			break
		end
	end
	if updated then
		save(history)
	end
end

--- Clear all history
function M.clear()
	save({})
	vim.notify("YT Control: History cleared", vim.log.levels.INFO)
end

return M
