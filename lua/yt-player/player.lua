---@mod yt-player.player Modern Player UI (Floating Mini HUD and Sidebar Panel)
local M = {}

local uv = vim.uv or vim.loop
local utils = require("yt-player.utils")
local state_mod = require("yt-player.state")
local theme = require("yt-player.ui.theme")
local window = require("yt-player.ui.window")
local visualizer = require("yt-player.ui.components.visualizer")
local layout = require("yt-player.ui.layout")
local deck = require("yt-player.ui.components.deck")

M.panel = { win_id = nil, buf_id = nil, update_timer = nil, last_hash = nil }
M.float = { win_id = nil, buf_id = nil, update_timer = nil, last_hash = nil }

M.config = {
	show_visualizer = true,
	visualizer_style = "wave", -- "wave", "bars", "dots", "none"
	progress_style = "slider", -- "slider", "blocks", "smooth"
	position = "top_right", -- "top_right", "bottom_right", "center"
	width = 54,
	show_queue = true,
	queue_limit = 5,
}

function M.setup(user_config)
	if user_config then
		M.config = vim.tbl_deep_extend("force", M.config, user_config)
	end
end

--- Shared record deck keeps the main player, sidebar, and mini visually related.
local function build_player_content(state, width, panel)
	local lines, highlights = {}, {}
	local available = math.max(1, width - 4)
	local function add(text, group)
		table.insert(lines, utils.safe_truncate("  " .. (text or ""), width))
		if group then table.insert(highlights, { line = #lines - 1, hl = group, col_start = 0, col_end = -1 }) end
	end
	if width >= 28 then
		local frame, marks = deck.render(state, available, { art = true, style = M.config.visualizer_style })
		for _, line in ipairs(frame) do add(line) end
		for _, mark in ipairs(marks) do
			table.insert(highlights, { line = mark.line, hl = mark.hl, col_start = (mark.col_start or 0) + 2, col_end = mark.col_end == -1 and -1 or mark.col_end + 2 })
		end
	else
		add(state.playing and "▶ PLAYING" or (state.title and "Ⅱ PAUSED" or "○ READY"), "YtPlayerAccent")
		add(utils.resolve_title(state.title or "Nothing playing", state), "YtPlayerTitleText")
		add(utils.format_time(state.position) .. " / " .. utils.format_time(state.duration), "YtPlayerProgress")
	end
	if M.config.show_visualizer and M.config.visualizer_style ~= "none" and width >= 40 and (panel or vim.o.lines >= 18) then
		add(layout.fit(visualizer.next_frame(M.config.visualizer_style, state.playing), available), "YtPlayerActive")
	end
	local queue = state.playlist or {}
	local current = math.max(1, (state.playlist_pos or 0) + 1)
	if panel and M.config.show_queue and #queue > 0 then
		add(layout.rule(available, "QUEUE", #queue .. " TRACKS"), "YtPlayerFrame")
		local inner = math.max(1, available - 4)
		local limit = M.config.queue_display_limit or M.config.queue_limit or 5
		for index = current, math.min(#queue, current + limit - 1) do
			local item = queue[index]
			local duration = (item.duration or 0) > 0 and utils.format_time(item.duration) or ""
			local row = layout.track(index, utils.resolve_title(item, state), duration, inner, index == current and theme.icon("playing") or " ")
			add(layout.inset(row, available), index == current and "YtPlayerPlaying" or "YtPlayerText")
		end
		add(layout.rule(available, nil, nil, true), "YtPlayerFrame")
	elseif not panel and queue[current + 1] then
		add(layout.pair("NEXT  " .. utils.resolve_title(queue[current + 1], state), utils.format_time(queue[current + 1].duration), available), "YtPlayerMuted")
	end
	if panel then
		add()
		add("Space Pause  ·  b/n Skip  ·  +/- Volume", "YtPlayerKeyHint")
		add("h/l Seek  ·  r Radio  ·  q Close", "YtPlayerMuted")
	end
	return lines, highlights
end

local function build_mini_content(state, width)
	return build_player_content(state, width, false)
end

local function build_panel_content(state, width)
	return build_player_content(state, width, true)
end

local function setup_keymaps(buf, is_float)
	local o = { noremap = true, silent = true, buffer = buf }
	local close = is_float and M.close_float or M.close_panel
	local refresh = is_float and function() M.refresh_float() end or function() M.refresh_panel() end

	local function cmd(c)
		return function()
			require("yt-player").command(c)
			vim.defer_fn(refresh, 150)
		end
	end

	vim.keymap.set("n", "q", close, o)
	vim.keymap.set("n", "<Esc>", close, o)
	vim.keymap.set("n", "p", cmd({ "set_property", "pause", false }), o)
	vim.keymap.set("n", "s", cmd({ "set_property", "pause", true }), o)
	vim.keymap.set("n", "t", cmd({ "cycle", "pause" }), o)
	vim.keymap.set("n", "<Space>", cmd({ "cycle", "pause" }), o)
	vim.keymap.set("n", "n", function()
		require("yt-player").command({ "playlist-next", "weak" })
		vim.defer_fn(refresh, 350)
	end, o)
	vim.keymap.set("n", "b", function()
		require("yt-player").command({ "playlist-prev", "weak" })
		vim.defer_fn(refresh, 350)
	end, o)
	vim.keymap.set("n", "m", cmd({ "cycle", "mute" }), o)
	vim.keymap.set("n", "+", cmd({ "add", "volume", 5 }), o)
	vim.keymap.set("n", "-", cmd({ "add", "volume", -5 }), o)
	vim.keymap.set("n", ">", cmd({ "add", "speed", 0.25 }), o)
	vim.keymap.set("n", "<", cmd({ "add", "speed", -0.25 }), o)
	vim.keymap.set("n", "l", cmd({ "seek", 5, "relative" }), o)
	vim.keymap.set("n", "h", cmd({ "seek", -5, "relative" }), o)
	vim.keymap.set("n", "L", cmd({ "seek", 30, "relative" }), o)
	vim.keymap.set("n", "H", cmd({ "seek", -30, "relative" }), o)

	for i = 0, 9 do
		vim.keymap.set("n", tostring(i), function()
			require("yt-player").command({ "seek", i * 10, "absolute-percent" })
			vim.defer_fn(refresh, 150)
		end, o)
	end
	vim.keymap.set("n", "G", function()
		require("yt-player").command({ "seek", 100, "absolute-percent" })
		vim.defer_fn(refresh, 150)
	end, o)

	vim.keymap.set("n", "r", function()
		require("yt-player.radio").toggle()
		vim.defer_fn(refresh, 150)
	end, o)

	vim.keymap.set("n", "R", function()
		local s = state_mod.get_current()
		if s.loop_file and s.loop_file ~= "no" and s.loop_file ~= false then
			require("yt-player").command({ "set_property", "loop-file", "no" })
			require("yt-player").command({ "set_property", "loop-playlist", "inf" })
		elseif s.loop_playlist and s.loop_playlist ~= "no" and s.loop_playlist ~= false then
			require("yt-player").command({ "set_property", "loop-playlist", "no" })
		else
			require("yt-player").command({ "set_property", "loop-file", "inf" })
		end
		vim.defer_fn(refresh, 150)
	end, o)
end

---------- FLOATING MINI HUD ----------

function M.refresh_float()
	if not M.float.win_id or not vim.api.nvim_win_is_valid(M.float.win_id) then
		M.close_float()
		return
	end

	local width = window.clamp_size(M.config.width or 54, 10)
	local state = state_mod.get_current()
	local lines, hls = build_mini_content(state, width)

	window.resize(M.float.win_id, width, #lines, M.config.position)
	local hash = table.concat(lines, "\n")
	if M.float.last_hash == hash then
		return
	end
	M.float.last_hash = hash

	window.render(M.float.buf_id, lines, hls)
end

function M.open_float()
	-- Floats live in one tabpage; reopen here rather than focus a hidden one
	if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) and not window.is_visible(M.float.win_id) then
		M.close_float()
	end
	if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) then
		M.refresh_float()
		vim.api.nvim_set_current_win(M.float.win_id)
		return
	end

	local width = window.clamp_size(M.config.width or 54, 10)
	local state = state_mod.get_current()
	local lines, hls = build_mini_content(state, width)
	local height = #lines

	local win_info = window.open_float({
		width = width,
		height = height,
		position = M.config.position or "top_right",
		title = string.format(" %s Now Playing ", theme.icon("music")),
		footer = " [Space] Pause  [n/b] Skip  [q] Hide ",
		border = (require("yt-player").config.ui or {}).border,
		enter = true,
	})

	M.float.win_id = win_info.win
	M.float.buf_id = win_info.buf
	M.float.last_hash = table.concat(lines, "\n")

	window.render(M.float.buf_id, lines, hls)
	setup_keymaps(M.float.buf_id, true)

	M.float.update_timer = uv.new_timer()
	M.float.update_timer:start(
		250,
		250,
		vim.schedule_wrap(function()
			if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) then
				M.refresh_float()
			else
				M.close_float()
			end
		end)
	)

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = M.float.buf_id,
		once = true,
		callback = function()
			M.close_float(true)
		end,
	})
end

function M.close_float(wiping)
	if M.float.update_timer then
		pcall(function()
			M.float.update_timer:stop()
			M.float.update_timer:close()
		end)
		M.float.update_timer = nil
	end
	local win, buf = M.float.win_id, M.float.buf_id
	M.float.win_id, M.float.buf_id = nil, nil
	if wiping then window.forget(win, buf) else window.safe_close(win, buf) end
	M.float.last_hash = nil
end

function M.toggle_float()
	if window.is_visible(M.float.win_id) then
		M.close_float()
	else
		M.open_float()
	end
end

---------- SIDEBAR PANEL ----------

function M.refresh_panel()
	if not M.panel.win_id or not vim.api.nvim_win_is_valid(M.panel.win_id) then
		M.close_panel()
		return
	end

	local width = vim.api.nvim_win_get_width(M.panel.win_id)
	local state = state_mod.get_current()
	local lines, hls = build_panel_content(state, width)

	local hash = table.concat(lines, "\n")
	if M.panel.last_hash == hash then
		return
	end
	M.panel.last_hash = hash

	window.render(M.panel.buf_id, lines, hls)
end

function M.open_panel()
	-- The sidebar split belongs to one tabpage; reopen it in the current one
	if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) and not window.is_visible(M.panel.win_id) then
		M.close_panel()
	end
	if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then
		M.refresh_panel()
		vim.api.nvim_set_current_win(M.panel.win_id)
		return
	end

	M.panel.buf_id = vim.api.nvim_create_buf(false, true)
	vim.bo[M.panel.buf_id].buftype = "nofile"
	vim.bo[M.panel.buf_id].bufhidden = "wipe"
	vim.bo[M.panel.buf_id].swapfile = false
	vim.bo[M.panel.buf_id].undolevels = -1
	vim.bo[M.panel.buf_id].filetype = "yt-player-panel"

	local panel_w = math.max(12, math.min(M.config.width or 45, math.floor(vim.o.columns * 0.5)))
	vim.cmd(string.format("botright %dvsplit", panel_w))
	M.panel.win_id = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(M.panel.win_id, M.panel.buf_id)

	local winhl = "Normal:YtPlayerNormal,NormalNC:YtPlayerNormal,NormalFloat:YtPlayerNormal,FloatBorder:YtPlayerBorder,CursorLine:YtPlayerSelected"
	vim.wo[M.panel.win_id].winhighlight = winhl
	vim.wo[M.panel.win_id].cursorline = false
	vim.wo[M.panel.win_id].number = false
	vim.wo[M.panel.win_id].relativenumber = false
	vim.wo[M.panel.win_id].signcolumn = "no"
	vim.wo[M.panel.win_id].wrap = false
	vim.wo[M.panel.win_id].winfixwidth = true
	pcall(function()
		vim.wo[M.panel.win_id].winfixbuf = true -- keep `:e file` out of the sidebar
	end)

	setup_keymaps(M.panel.buf_id, false)
	M.refresh_panel()

	M.panel.update_timer = uv.new_timer()
	M.panel.update_timer:start(
		250,
		250,
		vim.schedule_wrap(function()
			if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then
				M.refresh_panel()
			else
				M.close_panel()
			end
		end)
	)

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = M.panel.buf_id,
		once = true,
		callback = function()
			M.close_panel(true)
		end,
	})
end

function M.close_panel(wiping)
	if M.panel.update_timer then
		pcall(function()
			M.panel.update_timer:stop()
			M.panel.update_timer:close()
		end)
		M.panel.update_timer = nil
	end
	local win, buf = M.panel.win_id, M.panel.buf_id
	M.panel.win_id, M.panel.buf_id = nil, nil
	if wiping then window.forget(win, buf) else window.safe_close(win, buf) end
	M.panel.last_hash = nil
end

function M.toggle_panel()
	if window.is_visible(M.panel.win_id) then
		M.close_panel()
	else
		M.open_panel()
	end
end

return M
