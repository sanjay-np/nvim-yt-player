---@mod yt-player.queue Modern Interactive Queue Management
local M = {}

local state_mod = require("yt-player.state")
local mpv = require("yt-player.mpv")
local utils = require("yt-player.utils")
local theme = require("yt-player.ui.theme")
local window = require("yt-player.ui.window")

M.win_id = nil
M.buf_id = nil

local HEADER_OFFSET = 2

--- Render the queue list into the buffer
local function render_queue()
	if not M.buf_id or not vim.api.nvim_buf_is_valid(M.buf_id) then
		return
	end

	local state = state_mod.get_current()
	local plist = state.playlist or {}
	local win_w = (M.win_id and vim.api.nvim_win_is_valid(M.win_id)) and vim.api.nvim_win_get_width(M.win_id) or 70

	local lines = {}
	local hls = {}

	-- Header line
	local hdr = string.format("   %-4s %-10s %s", "#", "STATUS", "TITLE")
	table.insert(lines, hdr)
	table.insert(hls, { line = 0, hl = "YtPlayerAccent", virt_text = { { "DURATION   ", "YtPlayerAccent" } }, virt_text_pos = "right_align" })

	-- Separator
	local sep = string.rep("─", win_w - 4)
	table.insert(lines, "  " .. sep)
	table.insert(hls, { line = 1, hl = "YtPlayerSeparator", col_start = 0, col_end = -1 })

	if #plist == 0 then
		table.insert(lines, "")
		table.insert(lines, "   (Queue is currently empty)")
		table.insert(hls, { line = #lines - 1, hl = "YtPlayerMuted", col_start = 0, col_end = -1 })
	else
		for i, item in ipairs(plist) do
			local is_current = (i - 1 == state.playlist_pos)
			local status_icon = is_current and (theme.icon("playing") .. " PLAYING") or "         "
			local num_str = string.format("%2d.", i)

			local clean_title = utils.resolve_title(item, state)
			local dur = item.duration or item.length_sec
			local dur_str = dur and utils.format_time(dur) or ""

			-- Available title width
			local title_w = math.max(15, win_w - 32)
			local display_title = utils.safe_truncate(clean_title, title_w)

			local row = string.format("   %-4s %-10s %s", num_str, status_icon, display_title)
			table.insert(lines, row)

			local line_idx = #lines - 1
			if is_current then
				table.insert(hls, { line = line_idx, hl = "YtPlayerPlaying", col_start = 0, col_end = -1 })
				if dur_str ~= "" then
					table.insert(hls, { line = line_idx, virt_text = { { dur_str .. "   ", "YtPlayerPlaying" } }, virt_text_pos = "right_align" })
				end
			else
				table.insert(hls, { line = line_idx, hl = "YtPlayerText", col_start = 0, col_end = -1 })
				table.insert(hls, { line = line_idx, hl = "YtPlayerIndex", col_start = 3, col_end = 8 })
				if dur_str ~= "" then
					table.insert(hls, { line = line_idx, virt_text = { { dur_str .. "   ", "YtPlayerDuration" } }, virt_text_pos = "right_align" })
				end
			end
		end
	end

	window.render(M.buf_id, lines, hls)

	-- Update window title
	if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
		pcall(vim.api.nvim_win_set_config, M.win_id, {
			title = string.format(" %s Playback Queue (%d tracks) ", theme.icon("queue"), #plist),
			title_pos = "center",
		})
	end
end

local function get_cursor_item_index()
	if not M.win_id or not vim.api.nvim_win_is_valid(M.win_id) then
		return nil
	end
	local state = state_mod.get_current()
	local plist = state.playlist or {}
	if #plist == 0 then
		return nil
	end
	local cursor = vim.api.nvim_win_get_cursor(M.win_id)
	local r = cursor[1]
	if r <= HEADER_OFFSET then
		return nil
	end
	local idx = r - HEADER_OFFSET - 1 -- 0-indexed for mpv
	if idx < 0 or idx >= #plist then
		return nil
	end
	return idx
end

local function setup_keymaps()
	local o = { noremap = true, silent = true, buffer = M.buf_id }

	-- Close
	vim.keymap.set("n", "q", M.close, o)
	vim.keymap.set("n", "<Esc>", M.close, o)

	-- Play track
	vim.keymap.set("n", "<CR>", function()
		local idx = get_cursor_item_index()
		if idx then
			mpv.send_command({ "playlist-play-index", idx })
			vim.defer_fn(render_queue, 200)
		end
	end, o)

	-- Remove track
	vim.keymap.set("n", "dd", function()
		local idx = get_cursor_item_index()
		if idx then
			mpv.send_command({ "playlist-remove", idx })
			vim.defer_fn(render_queue, 200)
		end
	end, o)

	-- Move track down
	vim.keymap.set("n", "J", function()
		local idx = get_cursor_item_index()
		local state = state_mod.get_current()
		local plist = state.playlist or {}
		if idx and idx < #plist - 1 then
			mpv.send_command({ "playlist-move", idx, idx + 2 })
			local cur = vim.api.nvim_win_get_cursor(M.win_id)
			vim.defer_fn(function()
				render_queue()
				if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
					pcall(vim.api.nvim_win_set_cursor, M.win_id, { cur[1] + 1, cur[2] })
				end
			end, 150)
		end
	end, o)

	-- Move track up
	vim.keymap.set("n", "K", function()
		local idx = get_cursor_item_index()
		if idx and idx > 0 then
			mpv.send_command({ "playlist-move", idx, idx - 1 })
			local cur = vim.api.nvim_win_get_cursor(M.win_id)
			vim.defer_fn(function()
				render_queue()
				if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
					pcall(vim.api.nvim_win_set_cursor, M.win_id, { math.max(HEADER_OFFSET + 1, cur[1] - 1), cur[2] })
				end
			end, 150)
		end
	end, o)

	-- Clear queue
	vim.keymap.set("n", "c", function()
		mpv.send_command({ "playlist-clear" })
		vim.notify("YT Control: Queue cleared", vim.log.levels.INFO)
		vim.defer_fn(render_queue, 200)
	end, o)

	-- Shuffle queue
	vim.keymap.set("n", "S", function()
		mpv.send_command({ "playlist-shuffle" })
		vim.notify("YT Control: Queue shuffled", vim.log.levels.INFO)
		vim.defer_fn(render_queue, 200)
	end, o)
end

function M.open()
	if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
		render_queue()
		vim.api.nvim_set_current_win(M.win_id)
		return
	end

	local width = math.floor(vim.o.columns * 0.65)
	local height = math.floor(vim.o.lines * 0.65)

	local win_info = window.open_float({
		width = width,
		height = height,
		position = "center",
		title = string.format(" %s Playback Queue ", theme.icon("queue")),
		footer = " [↵] Play  [J/K] Move Down/Up  [dd] Remove  [c] Clear  [S] Shuffle  [q] Close ",
		cursorline = true,
		enter = true,
	})

	M.win_id = win_info.win
	M.buf_id = win_info.buf

	vim.bo[M.buf_id].filetype = "yt-player-queue"

	render_queue()
	setup_keymaps()

	-- Set cursor to active track if playing
	local state = state_mod.get_current()
	if state.playlist_pos and state.playlist and #state.playlist > 0 then
		local active_line = HEADER_OFFSET + state.playlist_pos + 1
		pcall(vim.api.nvim_win_set_cursor, M.win_id, { active_line, 0 })
	else
		pcall(vim.api.nvim_win_set_cursor, M.win_id, { HEADER_OFFSET + 1, 0 })
	end

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = M.buf_id,
		once = true,
		callback = function()
			M.win_id = nil
			M.buf_id = nil
		end,
	})
end

function M.close()
	window.safe_close(M.win_id, M.buf_id)
	M.win_id = nil
	M.buf_id = nil
end

return M
