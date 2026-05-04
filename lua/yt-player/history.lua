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
	local f = io.open(history_path(), "r")
	if not f then
		return {}
	end
	local content = f:read("*a")
	f:close()
	if content == "" then
		return {}
	end
	local ok, data = pcall(vim.json.decode, content)
	if not ok or type(data) ~= "table" then
		return {}
	end
	return data
end

--- Write history to disk
---@param data table[]
local function save(data)
	local f = io.open(history_path(), "w")
	if f then
		f:write(vim.json.encode(data))
		f:close()
	end
end

--- Add a track to history (newest first, deduplicated by URL)
---@param entry table {title, url, duration?}
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
		timestamp = os.time(),
	})

	-- Cap at max
	while #filtered > MAX_ENTRIES do
		table.remove(filtered)
	end

	save(filtered)
end

--- Clear all history
function M.clear()
	save({})
	vim.notify("YT Control: History cleared", vim.log.levels.INFO)
end

--- Format a relative time string
local function relative_time(ts)
	local diff = os.time() - ts
	if diff < 60 then
		return "just now"
	elseif diff < 3600 then
		return math.floor(diff / 60) .. "m ago"
	elseif diff < 86400 then
		return math.floor(diff / 3600) .. "h ago"
	else
		return math.floor(diff / 86400) .. "d ago"
	end
end

--- Open an interactive history picker
function M.open_picker()
	local history = M.get()
	if #history == 0 then
		vim.notify("YT Control: No history yet", vim.log.levels.INFO)
		return
	end

	local buf = vim.api.nvim_create_buf(false, true)
	local width = math.floor(vim.o.columns * 0.7)
	local height = math.min(math.floor(vim.o.lines * 0.8), #history * 3 + 3)
	local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
	local col = math.max(0, math.floor((vim.o.columns - width) / 2))

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " 🕐 Play History ",
		title_pos = "center",
	})

	vim.wo[win].cursorline = true

	-- Build display lines
	local lines = { " Recently Played", "" }
	for i, item in ipairs(history) do
		table.insert(lines, string.format(" %d. %s", i, item.title))
		table.insert(
			lines,
			string.format("    ⏱ %s  •  %s", utils.format_duration(item.duration), relative_time(item.timestamp))
		)
		table.insert(lines, "")
	end
	if #lines > 2 then
		table.remove(lines)
	end -- remove trailing spacer

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].buftype = "nofile"

	-- Highlight header
	local ns = vim.api.nvim_create_namespace("yt_history")
	vim.api.nvim_buf_add_highlight(buf, ns, "Title", 0, 0, -1)

	vim.api.nvim_win_set_cursor(win, { 3, 0 })

	-- Helpers
	local function get_current_item()
		local r = vim.api.nvim_win_get_cursor(win)[1]
		if r < 3 or #history == 0 then
			return nil
		end
		local idx = math.floor((r - 3) / 3) + 1
		return history[idx]
	end

	local function jump(dir)
		if #history == 0 then
			return
		end
		local r = vim.api.nvim_win_get_cursor(win)[1]
		if r < 3 then
			vim.api.nvim_win_set_cursor(win, { 3, 0 })
			return
		end
		local current_idx = math.floor((r - 3) / 3)
		local target_idx = math.max(0, math.min(#history - 1, current_idx + dir))
		vim.api.nvim_win_set_cursor(win, { 3 + (target_idx * 3), 0 })
	end

	local opts = { buffer = buf, silent = true }

	-- Play on Enter
	vim.keymap.set("n", "<CR>", function()
		local item = get_current_item()
		if item then
			require("yt-player").load(item.url)
			vim.api.nvim_win_close(win, true)
			vim.notify("YT Control: Playing → " .. item.title, vim.log.levels.INFO)
		end
	end, opts)

	-- Queue on 'a'
	local function queue_item()
		local item = get_current_item()
		if item then
			require("yt-player").queue(item)
		end
	end

	vim.keymap.set("n", "a", queue_item, opts)
	vim.keymap.set("n", "A", queue_item, opts)
	vim.keymap.set("n", "<C-a>", queue_item, opts)

	-- Save (s)
	vim.keymap.set("n", "s", function()
		local item = get_current_item()
		if item then
			require("yt-player.playlists").prompt_save(item)
		end
	end, opts)

	-- Navigation
	vim.keymap.set("n", "j", function()
		jump(1)
	end, opts)
	vim.keymap.set("n", "k", function()
		jump(-1)
	end, opts)
	vim.keymap.set("n", "<Tab>", function()
		jump(1)
	end, opts)
	vim.keymap.set("n", "<S-Tab>", function()
		jump(-1)
	end, opts)

	-- Close
	vim.keymap.set("n", "q", function()
		vim.api.nvim_win_close(win, true)
	end, opts)
	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, opts)
end

return M
