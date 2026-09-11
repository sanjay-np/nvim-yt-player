---@mod yt-player.player Player UI windows
local M = {}

local uv = vim.uv or vim.loop

M.panel = { win_id = nil, buf_id = nil, update_timer = nil }
M.float = { win_id = nil, buf_id = nil, update_timer = nil }



-- Highlights setup flag
M.highlights_setup = false

-- Module configuration (can be overridden via M.setup())
M.config = {
	show_visualizer = true,
	show_help = true,
	show_queue = true,
	queue_limit = 5,
	colors = true,
}

-- Setup function to override config
function M.setup(user_config)
	if user_config then
		M.config = vim.tbl_deep_extend("force", M.config, user_config)
	end
end

local utils = require("yt-player.utils")
local state_mod = require("yt-player.state")

local ns_id = vim.api.nvim_create_namespace("yt_player_ui")

-- Improved visualizer frames - rock-solid 1-cell characters only, zero alignment shifting
local visualizer_frames = {
	"▃ ▅ ▇ █ ▇ ▅ ▃   ▃ ▅ ▇ █ ▇ ▅ ▃",
	"▅ ▇ █ ▆ █ ▇ ▅ ▂ ▅ ▇ █ ▆ █ ▇ ▅",
	"▇ █ ▆ ▄ ▆ █ ▇ ▃ ▇ █ ▆ ▄ ▆ █ ▇",
	"█ ▆ ▄ ▂ ▄ ▆ █ ▅ █ ▆ ▄ ▂ ▄ ▆ █",
	"▆ ▄ ▂   ▂ ▄ ▆ ▇ ▆ ▄ ▂   ▂ ▄ ▆",
	"▄ ▂   ▂   ▂ ▄ ▆ ▄ ▂   ▂   ▂ ▄",
	"▂   ▂ ▃ ▂   ▂ ▄ ▂   ▂ ▃ ▂   ▂",
	"  ▂ ▃ ▅ ▃ ▂   ▂   ▂ ▃ ▅ ▃ ▂  ",
	"▂ ▃ ▅ ▇ ▅ ▃ ▂   ▂ ▃ ▅ ▇ ▅ ▃ ▂",
}
local frame_idx = 1

-- Spinning Vinyl Art with 8 animated frames
local vinyl_frames = {
	{ "╭───♫───╮", "│  💿   │", "│  ♪    │", "╰───────╯" },
	{ "╭───────╮", "│ ♩ 💿  │", "│       │", "╰───♬───╯" },
	{ "╭───♪───╮", "│   💿  │", "│    ♫  │", "╰───────╯" },
	{ "╭───────╮", "│  💿 ♬ │", "│       │", "╰───♩───╯" },
	{ "╭───♩───╮", "│  💿   │", "│  ♫    │", "╰───────╯" },
	{ "╭───────╮", "│ ♪ 💿  │", "│       │", "╰───♬───╯" },
	{ "╭───♬───╮", "│   💿  │", "│    ♩  │", "╰───────╯" },
	{ "╭───────╮", "│  💿 ♫ │", "│       │", "╰───♪───╯" },
}

-- Paused cover art
local paused_art = {
	"╭───────╮",
	"│  💿   │",
	"│  💤   │",
	"╰───────╯",
}

-- Track panel/float window widths
local panel_width = 40
local float_width = 50

local function progress_bar(position, duration, width)
	width = width or 20
	if not duration or duration <= 0 then
		return string.rep("─", width), 0
	end
	local pct = math.min((position or 0) / duration, 1)
	local filled = math.floor(pct * width)

	if filled == 0 then
		return "○" .. string.rep("─", width - 1), 0
	elseif filled >= width then
		return string.rep("━", width - 1) .. "●", width
	else
		return string.rep("━", filled) .. "●" .. string.rep("─", width - filled - 1), filled
	end
end

local function mini_progress_bar(position, duration, width)
	width = width or 15
	if not duration or duration <= 0 then
		return string.rep("─", width)
	end
	local pct = math.min((position or 0) / duration, 1)
	local filled = math.floor(pct * width)
	if filled == 0 then
		return "○" .. string.rep("─", width - 1)
	elseif filled >= width then
		return string.rep("━", width - 1) .. "●"
	else
		return string.rep("━", filled) .. "●" .. string.rep("─", width - filled - 1)
	end
end

local function center_text(str, width)
	str = utils.safe_truncate(str or "", width)
	local len = vim.fn.strdisplaywidth(str)
	local left = math.floor((width - len) / 2)
	local right = width - len - left
	return string.rep(" ", left) .. str .. string.rep(" ", right)
end

local function pad_right(str, width)
	return utils.pad_right(utils.safe_truncate(str or "", width), width)
end

-- Proper border width calculation
local function make_header(title, width)
	local content = "─ " .. title .. " ─"
	local remaining = width - vim.fn.strdisplaywidth(content) - 2
	if remaining > 0 then
		content = content .. string.rep("─", remaining)
	end
	return "╭" .. content .. "╮"
end

local function make_footer(width)
	return "╰" .. string.rep("─", width - 2) .. "╯"
end

local function make_section_header(title, width)
	local content = "─ " .. title
	local remaining = width - vim.fn.strdisplaywidth(content) - 2
	if remaining > 0 then
		content = content .. string.rep("─", remaining)
	end
	return "╭" .. content .. "╮"
end

local _static_cache = { width = -1 }

local function get_cached_header(title, width)
	if _static_cache.width ~= width then
		_static_cache = { width = width }
	end
	local k = "h_" .. title
	if not _static_cache[k] then
		_static_cache[k] = make_header(title, width)
	end
	return _static_cache[k]
end

local function get_cached_section_header(title, width)
	if _static_cache.width ~= width then
		_static_cache = { width = width }
	end
	local k = "s_" .. title
	if not _static_cache[k] then
		_static_cache[k] = make_section_header(title, width)
	end
	return _static_cache[k]
end

local function get_cached_footer(width)
	if _static_cache.width ~= width then
		_static_cache = { width = width }
	end
	if not _static_cache.footer then
		_static_cache.footer = make_footer(width)
	end
	return _static_cache.footer
end

-- Setup highlight groups (Dracula-inspired colors for dark theme with ANSI fallbacks)
local function setup_highlights()
	-- Only setup once
	if M.highlights_setup then
		return
	end

	local highlights = {
		YtPlayerTitle = { fg = "#bd93f9", ctermfg = 141, bold = true, cterm = { bold = true } }, -- Purple
		YtPlayerArtist = { fg = "#6272a4", ctermfg = 60 }, -- Grayish blue
		YtPlayerProgress = { fg = "#50fa7b", ctermfg = 84 }, -- Green
		YtPlayerProgressBg = { fg = "#44475a", ctermfg = 238 }, -- Dark gray
		YtPlayerControls = { fg = "#8be9fd", ctermfg = 117 }, -- Cyan
		YtPlayerVolume = { fg = "#ffb86c", ctermfg = 215 }, -- Orange
		YtPlayerVolumeBg = { fg = "#44475a", ctermfg = 238 }, -- Dark gray
		YtPlayerRadio = { fg = "#ff79c6", ctermfg = 212 }, -- Pink
		YtPlayerQueue = { fg = "#f8f8f2", ctermfg = 255 }, -- White
		YtPlayerQueueCurrent = { fg = "#50fa7b", ctermfg = 84, bold = true, cterm = { bold = true } }, -- Green bold
		YtPlayerBorder = { fg = "#6272a4", ctermfg = 60 }, -- Gray border
		YtPlayerHelp = { fg = "#6272a4", ctermfg = 60 }, -- Gray help
	}

	for name, opts in pairs(highlights) do
		vim.api.nvim_set_hl(0, name, opts)
	end

	M.highlights_setup = true
end

-- Get actual window width for dynamic sizing
local function get_win_width(win_id)
	if win_id and vim.api.nvim_win_is_valid(win_id) then
		return vim.api.nvim_win_get_width(win_id)
	end
	return nil
end

-- Determine target width based on window
local function get_target_width(is_float)
	if is_float then
		return float_width
	else
		return panel_width
	end
end

-- Update stored width from actual window
local function update_stored_width(win_id, is_float)
	local w = get_win_width(win_id)
	if w and w > 10 then
		if is_float then
			float_width = w
		else
			panel_width = w
		end
	end
end

local function build_lines(state, is_float)
	local is_playing = state.playing
	local width = get_target_width(is_float)
	local content_width = width - 4

	-- Animate visualizer if playing
	if is_playing then
		frame_idx = (frame_idx % #visualizer_frames) + 1
	end

	local title = state.title or "No Track"
	local artist = state.artist or "Unknown Artist"
	if artist == "" then
		artist = "Unknown Artist"
	end

	local vol = math.floor(state.volume or 100)
	local speed_str = string.format("%.1fx", state.speed or 1)

	local pos_str = utils.format_time(state.position)
	local dur_str = utils.format_time(state.duration)

	local lines = {}
	local highlights = {} -- Store highlights for each line

	-- Helper to apply precise border highlighting (only highlights content inside boundaries)
	local function add_row_highlights(line_idx, highlight, padded_len)
		-- Left border (3-byte UTF-8 │ plus 1 space = 4 bytes)
		table.insert(highlights, { line = line_idx, hl = "YtPlayerBorder", col_start = 0, col_end = 3 })
		-- Content
		if highlight then
			table.insert(highlights, { line = line_idx, hl = highlight, col_start = 4, col_end = 4 + padded_len })
		end
		-- Right border (1 space plus 3-byte UTF-8 │)
		table.insert(highlights, { line = line_idx, hl = "YtPlayerBorder", col_start = 4 + padded_len + 1, col_end = -1 })
	end

	-- Helper to add bordered row with optional highlight
	local function add_row(content, highlight)
		local padded = pad_right(content, content_width)
		table.insert(lines, string.format("│ %s │", padded))
		if M.config.colors then
			add_row_highlights(#lines - 1, highlight, #padded)
		end
	end

	local function add_center(content, highlight)
		local padded = center_text(content, content_width)
		table.insert(lines, string.format("│ %s │", padded))
		if M.config.colors then
			add_row_highlights(#lines - 1, highlight, #padded)
		end
	end

	-- Helper to add a header/footer/section-header border-only line
	local function add_border_line(border_str)
		table.insert(lines, border_str)
		if M.config.colors then
			table.insert(highlights, { line = #lines - 1, hl = "YtPlayerBorder", col_start = 0, col_end = -1 })
		end
	end

	-- Helper to add a seamless box-splitting horizontal separator
	local function add_split_line()
		table.insert(lines, string.format("├%s┤", string.rep("─", width - 2)))
		if M.config.colors then
			table.insert(highlights, { line = #lines - 1, hl = "YtPlayerBorder", col_start = 0, col_end = -1 })
		end
	end

	-- Calculate split: album art + track info
	local art_width = 9
	local info_width = content_width - art_width - 1

	-- Helper to add album art + track info row with clean borders (dynamically computed byte lengths)
	local function add_art_row(art_line, info_line, hl)
		local padded_info = pad_right(info_line, info_width)
		table.insert(lines, string.format("│ %s %s │", art_line, padded_info))
		if M.config.colors then
			local line_idx = #lines - 1
			local art_len = string.len(art_line)
			local info_len = string.len(padded_info)
			
			-- Left border
			table.insert(highlights, { line = line_idx, hl = "YtPlayerBorder", col_start = 0, col_end = 3 })
			-- Album Art
			table.insert(highlights, { line = line_idx, hl = "YtPlayerArtist", col_start = 4, col_end = 4 + art_len })
			-- Track info
			if hl then
				table.insert(highlights, { line = line_idx, hl = hl, col_start = 4 + art_len + 1, col_end = 4 + art_len + 1 + info_len })
			end
			-- Right border
			table.insert(highlights, { line = line_idx, hl = "YtPlayerBorder", col_start = 4 + art_len + 1 + info_len + 1, col_end = -1 })
		end
	end

	-- Helper to add a multi-colored progress bar row
	local function add_progress_row(pos_str, prog_bar, dur_str, filled_count, bar_width)
		local prog_line = string.format("%s %s %s", pos_str, prog_bar, dur_str)
		local padded = pad_right(prog_line, content_width)
		table.insert(lines, string.format("│ %s │", padded))

		if M.config.colors then
			local line_idx = #lines - 1
			-- Left border
			table.insert(highlights, { line = line_idx, hl = "YtPlayerBorder", col_start = 0, col_end = 3 })

			-- Elapsed time
			local len_pos = string.len(pos_str)
			table.insert(highlights, { line = line_idx, hl = "YtPlayerHelp", col_start = 4, col_end = 4 + len_pos })

			-- Space between pos_str and progress bar (1 byte)
			local prog_start = 4 + len_pos + 1

			-- Filled progress bar part
			local filled_bytes = filled_count * 3
			table.insert(highlights, { line = line_idx, hl = "YtPlayerProgress", col_start = prog_start, col_end = prog_start + filled_bytes })

			-- Unfilled progress bar part
			local unfilled_bytes = (bar_width - filled_count) * 3
			if unfilled_bytes > 0 then
				table.insert(highlights, { line = line_idx, hl = "YtPlayerProgressBg", col_start = prog_start + filled_bytes, col_end = prog_start + filled_bytes + unfilled_bytes })
			end

			-- Space between progress bar and dur_str (1 byte)
			local dur_start = prog_start + bar_width * 3 + 1
			local len_dur = string.len(dur_str)

			-- Duration time
			table.insert(highlights, { line = line_idx, hl = "YtPlayerHelp", col_start = dur_start, col_end = dur_start + len_dur })

			-- Right border
			table.insert(highlights, { line = line_idx, hl = "YtPlayerBorder", col_start = 4 + #padded + 1, col_end = -1 })
		end
	end

	-- Helper to add a multi-colored volume bar row
	local function add_volume_row(vol_icon, vol_gauge, vol, speed_str, vol_bars)
		local vol_line = string.format("%s %s %d%%   ⚡ %s", vol_icon, vol_gauge, vol, speed_str)
		local padded = pad_right(vol_line, content_width)
		table.insert(lines, string.format("│ %s │", padded))

		if M.config.colors then
			local line_idx = #lines - 1
			-- Left border
			table.insert(highlights, { line = line_idx, hl = "YtPlayerBorder", col_start = 0, col_end = 3 })

			-- Volume icon (starts at 4, length is #vol_icon)
			local len_icon = string.len(vol_icon)
			table.insert(highlights, { line = line_idx, hl = "YtPlayerVolume", col_start = 4, col_end = 4 + len_icon })

			-- Space between icon and gauge (1 byte)
			local gauge_start = 4 + len_icon + 1

			-- Filled volume blocks
			local filled_bytes = vol_bars * 3
			if filled_bytes > 0 then
				table.insert(highlights, { line = line_idx, hl = "YtPlayerVolume", col_start = gauge_start, col_end = gauge_start + filled_bytes })
			end

			-- Unfilled volume blocks
			local unfilled_bytes = (10 - vol_bars) * 3
			if unfilled_bytes > 0 then
				table.insert(highlights, { line = line_idx, hl = "YtPlayerVolumeBg", col_start = gauge_start + filled_bytes, col_end = gauge_start + filled_bytes + unfilled_bytes })
			end

			-- Suffix (%d%%   ⚡ %s) starts at gauge_start + 30 + 1 (accounts for space)
			local suffix_start = gauge_start + 30 + 1
			table.insert(highlights, { line = line_idx, hl = "YtPlayerVolume", col_start = suffix_start, col_end = 4 + #padded })

			-- Right border
			table.insert(highlights, { line = line_idx, hl = "YtPlayerBorder", col_start = 4 + #padded + 1, col_end = -1 })
		end
	end

	-- ╭─ Header ───────────────────────╮
	-- LAYER 1: Track title + artist - PROMINENT
	add_border_line(get_cached_header("Now Playing", width))

	-- Animated vinyl cover art selection
	local album_art
	if is_playing then
		album_art = vinyl_frames[((frame_idx - 1) % #vinyl_frames) + 1]
	else
		album_art = paused_art
	end

	-- Add album art + track info row
	for i, art_line in ipairs(album_art) do
		local info_line = ""
		local hl = nil
		if i == 1 then
			info_line = utils.safe_truncate(title, info_width)
			hl = "YtPlayerTitle"
		elseif i == 2 then
			info_line = utils.safe_truncate(artist, info_width)
			hl = "YtPlayerArtist"
		elseif i == 3 then
			-- Duration info
			info_line = string.format("⏱ %s / %s", pos_str, dur_str)
		else
			info_line = ""
		end
		add_art_row(art_line, info_line, hl)
	end

	-- Visualizer
	if M.config.show_visualizer then
		local vis_frame = is_playing and visualizer_frames[frame_idx] or " ▂ ▃ ▄ ▃ ▂   ▂ ▃ ▄ ▃ ▂ "
		add_center(vis_frame, "YtPlayerProgress")
	end

	-- Layer 2: Playback status + progress (multi-colored)
	local bar_width = math.max(4, width - 22)
	local prog_bar, filled = progress_bar(state.position, state.duration, bar_width)
	local filled_count = math.max(1, math.min(bar_width, filled + 1))
	add_progress_row(pos_str, prog_bar, dur_str, filled_count, bar_width)

	-- Layer 3: Volume + Speed (multi-colored)
	local vol_icon = (state.muted or vol == 0) and "🔇" or (vol > 50 and "🔊" or "🔉")
	local vol_bars = math.max(0, math.min(10, math.floor(vol / 10)))
	local vol_gauge = string.rep("▰", vol_bars) .. string.rep("▱", 10 - vol_bars)
	add_volume_row(vol_icon, vol_gauge, vol, speed_str, vol_bars)

	-- Loop indicator
	local mode_str = ""
	if state.loop_file and state.loop_file ~= "no" and state.loop_file ~= false then
		mode_str = "🔂 Track"
	elseif state.loop_playlist and state.loop_playlist ~= "no" and state.loop_playlist ~= false then
		mode_str = "🔁 Playlist"
	end

	-- Controls: compact consolidated dashboard icons
	local ctrl_icon = is_playing and "⏸" or "▶"
	local mode_tag = state.radio_enabled and "📻 Radio" or (mode_str ~= "" and mode_str or "🔀 Normal")
	local ctrl = string.format("⏮  %s  ⏭    %s    %s", ctrl_icon, vol_icon, mode_tag)
	
	add_split_line()
	add_center(ctrl, "YtPlayerControls")

	-- Footer
	add_border_line(get_cached_footer(width))

	-- Layer 4: Help section - reduced to 1 line (conditional)
	if M.config.show_help then
		add_border_line(get_cached_section_header("Controls", width))
		add_row("[p/s/t]Play [b/n]Nav [r]Radio [</>]Spd [0-9]Seek [q]Exit", "YtPlayerHelp")
		add_border_line(get_cached_footer(width))
	end

	-- Compact Queue with duration (conditional)
	if M.config.show_queue and state.playlist and #state.playlist > 0 then
		local count_txt = string.format("%d/%d", (state.playlist_pos or 0) + 1, #state.playlist)

		add_border_line(get_cached_section_header("Queue (" .. count_txt .. ")", width))

		local limit = M.config.queue_limit
		local start_idx = math.max(1, (state.playlist_pos or 0))
		local end_idx = math.min(#state.playlist, start_idx + limit - 1)

		for i = start_idx, end_idx do
			local item = state.playlist[i]
			local is_current = (i - 1 == state.playlist_pos)
			local prefix = is_current and "▸" or "│"

			local item_title = item.title
				or (state.playlist_meta and state.playlist_meta[item.filename])
				or item.filename
				or "Unknown"

			-- Get duration if available
			local dur = item.duration or item.length_sec
			local dur_str = dur and utils.format_time(dur) or ""

			-- Format: "▸ 1. Track Title        3:45" or "│ 2. Track Title        3:45"
			local qitem = string.format(
				"%s %d. %s%s",
				prefix,
				i,
				pad_right(utils.safe_truncate(item_title, width - 16), width - 16),
				dur_str
			)

			local hl = is_current and "YtPlayerQueueCurrent" or "YtPlayerQueue"

			add_row(qitem, hl)

			-- Visual separator after current track
			if is_current and i < end_idx then
				add_row(string.rep("─", content_width), "YtPlayerBorder")
			end
		end

		if end_idx < #state.playlist then
			add_row(string.format("+%d more", #state.playlist - end_idx))
		end
		add_border_line(get_cached_footer(width))
	end

	return lines, highlights
end

local function calc_width(lines)
	local max = 0
	for _, line in ipairs(lines) do
		local w = vim.fn.strdisplaywidth(line)
		if w > max then
			max = w
		end
	end
	return math.max(max, 30)
end

local function refresh_instance(inst, is_float)
	if not inst.buf_id or not vim.api.nvim_buf_is_valid(inst.buf_id) then
		return false
	end
	if not inst.win_id or not vim.api.nvim_win_is_valid(inst.win_id) then
		return false
	end

	-- Update stored width from actual window
	update_stored_width(inst.win_id, is_float)

	local lines, highlights = build_lines(state_mod.get_current(), is_float)
	local state_hash = table.concat(lines, "\n")

	if inst.last_hash == state_hash then
		return true -- No structural changes, skip redraw
	end
	inst.last_hash = state_hash

	vim.bo[inst.buf_id].modifiable = true
	vim.api.nvim_buf_set_lines(inst.buf_id, 0, -1, false, lines)
	vim.bo[inst.buf_id].modifiable = false

	-- Apply highlights
	if highlights and #highlights > 0 then
		vim.api.nvim_buf_clear_namespace(inst.buf_id, ns_id, 0, -1)
		for _, hl_info in ipairs(highlights) do
			local col_start = hl_info.col_start or 0
			local col_end = hl_info.col_end or -1
			pcall(vim.api.nvim_buf_add_highlight, inst.buf_id, ns_id, hl_info.hl, hl_info.line, col_start, col_end)
		end
	end

	if is_float then
		vim.api.nvim_win_set_config(inst.win_id, { width = calc_width(lines), height = #lines })
	end
	return true
end

local function refresh_panel()
	if not refresh_instance(M.panel, false) then
		M.close_panel()
	end
end

local function refresh_float()
	if not refresh_instance(M.float, true) then
		M.close_float()
	end
end

local function setup_keymaps(buf, is_float)
	local o = { noremap = true, silent = true, buffer = buf }
	local refresh = is_float and refresh_float or refresh_panel
	local close = is_float and M.close_float or M.close_panel
	local cmd = function(c)
		return function()
			require("yt-player").command(c)
			vim.defer_fn(refresh, 200)
		end
	end

	vim.keymap.set("n", "q", close, o)
	vim.keymap.set("n", "<Esc>", close, o)
	vim.keymap.set("n", "p", cmd({ "set_property", "pause", false }), o)
	vim.keymap.set("n", "s", cmd({ "set_property", "pause", true }), o)
	vim.keymap.set("n", "t", cmd({ "cycle", "pause" }), o)
	vim.keymap.set("n", "n", function()
		require("yt-player").command({ "playlist-next", "weak" })
		vim.defer_fn(refresh, 500)
	end, o)
	vim.keymap.set("n", "b", function()
		require("yt-player").command({ "playlist-prev", "weak" })
		vim.defer_fn(refresh, 500)
	end, o)
	vim.keymap.set("n", "m", cmd({ "cycle", "mute" }), o)
	vim.keymap.set("n", ">", cmd({ "add", "speed", 0.25 }), o)
	vim.keymap.set("n", "<", cmd({ "add", "speed", -0.25 }), o)
	vim.keymap.set("n", "+", cmd({ "add", "volume", 5 }), o)
	vim.keymap.set("n", "-", cmd({ "add", "volume", -5 }), o)
	vim.keymap.set("n", "l", cmd({ "seek", 5, "relative" }), o)
	vim.keymap.set("n", "h", cmd({ "seek", -5, "relative" }), o)
	vim.keymap.set("n", "L", cmd({ "seek", 30, "relative" }), o)
	vim.keymap.set("n", "H", cmd({ "seek", -30, "relative" }), o)

	-- Keyboard seeking: 0-9 jump to 0%-90%, G goes to end
	for i = 0, 9 do
		local pct = i * 10
		vim.keymap.set("n", tostring(i), function()
			require("yt-player").command({ "seek", pct, "absolute-percent" })
			vim.defer_fn(refresh, 200)
		end, o)
	end
	vim.keymap.set("n", "G", function()
		require("yt-player").command({ "seek", 100, "absolute-percent" })
		vim.defer_fn(refresh, 200)
	end, o)

	-- Loop / Repeat controls
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
		vim.defer_fn(refresh, 200)
	end, o)

	-- Radio toggle control
	vim.keymap.set("n", "r", function()
		require("yt-player.radio").toggle()
		vim.defer_fn(refresh, 200)
	end, o)



end

---------- PANEL ----------

function M.open_panel()
	-- Setup highlights if enabled
	if M.config.colors then
		setup_highlights()
	end

	if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then
		refresh_panel()
		vim.api.nvim_set_current_win(M.panel.win_id)
		return
	end

	local lines, highlights = build_lines(state_mod.get_current(), false)

	M.panel.buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(M.panel.buf_id, 0, -1, false, lines)

	if highlights and #highlights > 0 then
		for _, hl_info in ipairs(highlights) do
			local col_start = hl_info.col_start or 0
			local col_end = hl_info.col_end or -1
			pcall(vim.api.nvim_buf_add_highlight, M.panel.buf_id, ns_id, hl_info.hl, hl_info.line, col_start, col_end)
		end
	end
	M.panel.last_hash = table.concat(lines, "\n")

	vim.bo[M.panel.buf_id].modifiable = false
	vim.bo[M.panel.buf_id].bufhidden = "wipe"
	vim.bo[M.panel.buf_id].buftype = "nofile"
	vim.bo[M.panel.buf_id].filetype = "yt-player-player"
	vim.bo[M.panel.buf_id].swapfile = false

	vim.cmd("botright 45vsplit")
	M.panel.win_id = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(M.panel.win_id, M.panel.buf_id)

	-- Get actual panel width after creation
	panel_width = vim.api.nvim_win_get_width(M.panel.win_id)

	vim.wo[M.panel.win_id].cursorline = false
	vim.wo[M.panel.win_id].number = false
	vim.wo[M.panel.win_id].relativenumber = false
	vim.wo[M.panel.win_id].signcolumn = "no"
	vim.wo[M.panel.win_id].wrap = false
	vim.wo[M.panel.win_id].winfixwidth = true -- Prevent width from changing on layout resize

	setup_keymaps(M.panel.buf_id, false)

	M.panel.update_timer = uv.new_timer()
	M.panel.update_timer:start(
		200,
		200,
		vim.schedule_wrap(function()
			if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then
				refresh_panel()
			else
				M.close_panel()
			end
		end)
	)

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = M.panel.buf_id,
		once = true,
		callback = function()
			if M.panel.update_timer then
				pcall(function()
					M.panel.update_timer:stop()
					M.panel.update_timer:close()
				end)
			end
			M.panel.update_timer = nil
			M.panel.win_id = nil
			M.panel.buf_id = nil
		end,
	})
end

function M.close_panel()
	if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then
		vim.api.nvim_win_close(M.panel.win_id, true)
	end
end

function M.toggle_panel()
	if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then
		M.close_panel()
	else
		M.open_panel()
	end
end

---------- FLOAT ----------

function M.open_float()
	-- Setup highlights if enabled
	if M.config.colors then
		setup_highlights()
	end

	if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) then
		refresh_float()
		vim.api.nvim_set_current_win(M.float.win_id)
		return
	end

	local lines, highlights = build_lines(state_mod.get_current(), true)
	local width, height = calc_width(lines), #lines

	M.float.buf_id = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(M.float.buf_id, 0, -1, false, lines)

	if highlights and #highlights > 0 then
		for _, hl_info in ipairs(highlights) do
			local col_start = hl_info.col_start or 0
			local col_end = hl_info.col_end or -1
			pcall(vim.api.nvim_buf_add_highlight, M.float.buf_id, ns_id, hl_info.hl, hl_info.line, col_start, col_end)
		end
	end
	M.float.last_hash = table.concat(lines, "\n")

	vim.bo[M.float.buf_id].modifiable = false
	vim.bo[M.float.buf_id].bufhidden = "wipe"
	vim.bo[M.float.buf_id].buftype = "nofile"
	vim.bo[M.float.buf_id].filetype = "yt-player-player"
	vim.bo[M.float.buf_id].swapfile = false

	M.float.win_id = vim.api.nvim_open_win(M.float.buf_id, true, {
		relative = "editor",
		row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		width = width,
		height = height,
		style = "minimal",
	})

	vim.wo[M.float.win_id].cursorline = false
	vim.wo[M.float.win_id].number = false
	vim.wo[M.float.win_id].relativenumber = false
	vim.wo[M.float.win_id].signcolumn = "no"
	vim.wo[M.float.win_id].foldcolumn = "0"
	vim.wo[M.float.win_id].wrap = false
	if vim.fn.has("nvim-0.9") == 1 then
		vim.wo[M.float.win_id].statuscolumn = ""
	end

	setup_keymaps(M.float.buf_id, true)

	M.float.update_timer = uv.new_timer()
	M.float.update_timer:start(
		1000,
		1000,
		vim.schedule_wrap(function()
			if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) then
				refresh_float()
			else
				M.close_float()
			end
		end)
	)

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = M.float.buf_id,
		once = true,
		callback = function()
			if M.float.update_timer then
				pcall(function()
					M.float.update_timer:stop()
					M.float.update_timer:close()
				end)
			end
			M.float.update_timer = nil
			M.float.win_id = nil
			M.float.buf_id = nil
		end,
	})
end

function M.close_float()
	if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) then
		vim.api.nvim_win_close(M.float.win_id, true)
	end
end

function M.toggle_float()
	if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) then
		M.close_float()
	else
		M.open_float()
	end
end



return M
