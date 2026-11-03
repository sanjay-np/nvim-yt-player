---@mod yt-player.history Persistent play history and modern picker
local M = {}

local utils = require("yt-player.utils")
local theme = require("yt-player.ui.theme")
local window = require("yt-player.ui.window")
local state_mod = require("yt-player.state")

local MAX_ENTRIES = 100

local function history_path()
	return vim.fn.stdpath("data") .. "/yt-player-history.json"
end

--- Read history from disk
---@return table[]
function M.get()
	local data, is_corrupt = utils.read_json_file(history_path(), {})
	if is_corrupt then
		vim.notify("YT Control: Warning - history file corrupted, preserving existing data", vim.log.levels.WARN)
	end
	return data
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

--- Format a relative time string
local function relative_time(ts)
	if not ts or type(ts) ~= "number" then
		return "recently"
	end
	local diff = os.time() - ts
	if diff < 0 then
		return "just now"
	elseif diff < 60 then
		return "just now"
	elseif diff < 3600 then
		return math.floor(diff / 60) .. "m ago"
	elseif diff < 86400 then
		return math.floor(diff / 3600) .. "h ago"
	else
		return math.floor(diff / 86400) .. "d ago"
	end
end

local HEADER_OFFSET = 2

--- Open the modern history picker
function M.open_picker()
	local history = M.get()
	if #history == 0 then
		vim.notify("YT Control: No play history yet", vim.log.levels.INFO)
		return
	end

	local width = math.floor(vim.o.columns * 0.7)
	local height = math.min(math.floor(vim.o.lines * 0.75), math.max(10, #history + 4))

	local win_info = window.open_float({
		width = width,
		height = height,
		position = "center",
		title = string.format(" %s Play History (%d tracks) ", theme.icon("history"), #history),
		footer = " [↵] Play  [a] Queue  [s] Save to Playlist  [c] Clear  [q] Close ",
		cursorline = true,
		enter = true,
	})

	local win = win_info.win
	local buf = win_info.buf

	local function render()
		history = M.get()
		local current_state = state_mod.get_current()
		local cur_pos = current_state.playlist_pos
		local cur_filename = (current_state.playlist and cur_pos and current_state.playlist[cur_pos + 1])
			and current_state.playlist[cur_pos + 1].filename or nil

		local lines = {}
		local hls = {}

		-- Header line
		local hdr = string.format("   %-4s %-10s %s", "#", "STATUS", "TITLE")
		table.insert(lines, hdr)
		table.insert(hls, {
			line = 0,
			hl = "YtPlayerAccent",
			virt_text = { { "TIME  •  DURATION   ", "YtPlayerAccent" } },
			virt_text_pos = "right_align",
		})

		-- Separator
		local sep = string.rep("─", width - 4)
		table.insert(lines, "  " .. sep)
		table.insert(hls, { line = 1, hl = "YtPlayerSeparator", col_start = 0, col_end = -1 })

		for i, item in ipairs(history) do
			local is_playing = cur_filename and (item.url == cur_filename)
			local status_icon = is_playing and (theme.icon("playing") .. " PLAYING") or "         "
			local num_str = string.format("%2d.", i)
			local clean_title = utils.safe_truncate(item.title or "Unknown", width - 36)

			local dur_str = (item.duration and item.duration > 0) and utils.format_time(item.duration) or "--:--"
			local rel_str = relative_time(item.timestamp)

			local row = string.format("   %-4s %-10s %s", num_str, status_icon, clean_title)
			table.insert(lines, row)

			local line_idx = #lines - 1
			if is_playing then
				table.insert(hls, { line = line_idx, hl = "YtPlayerPlaying", col_start = 0, col_end = -1 })
			else
				table.insert(hls, { line = line_idx, hl = "YtPlayerText", col_start = 0, col_end = -1 })
				table.insert(hls, { line = line_idx, hl = "YtPlayerIndex", col_start = 3, col_end = 8 })
			end

			local badge_text = string.format("%s  •  %s   ", rel_str, dur_str)
			table.insert(hls, {
				line = line_idx,
				virt_text = { { badge_text, is_playing and "YtPlayerPlaying" or "YtPlayerMuted" } },
				virt_text_pos = "right_align",
			})
		end

		window.render(buf, lines, hls)
	end

	render()

	local o = { buffer = buf, silent = true, noremap = true }

	local function close()
		window.safe_close(win, buf)
	end

	vim.keymap.set("n", "q", close, o)
	vim.keymap.set("n", "<Esc>", close, o)

	local function get_current_item()
		local r = vim.api.nvim_win_get_cursor(win)[1]
		local idx = r - HEADER_OFFSET
		if idx < 1 or idx > #history then
			return nil
		end
		return history[idx]
	end

	-- Play track
	vim.keymap.set("n", "<CR>", function()
		local item = get_current_item()
		if item then
			require("yt-player").load(item.url)
			vim.defer_fn(render, 200)
		end
	end, o)

	-- Queue track
	vim.keymap.set("n", "a", function()
		local item = get_current_item()
		if item then
			require("yt-player").queue(item)
		end
	end, o)

	-- Save to playlist
	vim.keymap.set("n", "s", function()
		local item = get_current_item()
		if item then
			require("yt-player.playlists").prompt_save(item)
		end
	end, o)

	-- Clear history
	vim.keymap.set("n", "c", function()
		vim.ui.select({ "No, Keep History", "Yes, Clear All History" }, {
			prompt = "Are you sure you want to clear your play history?",
		}, function(choice)
			if choice == "Yes, Clear All History" then
				M.clear()
				close()
			end
		end)
	end, o)

	pcall(vim.api.nvim_win_set_cursor, win, { HEADER_OFFSET + 1, 0 })
end

return M
