---@mod yt-player.search YouTube search via yt-dlp
local M = {}

local uv = vim.uv or vim.loop
local utils = require("yt-player.utils")

-- =============================================================================
-- HIGHLIGHTS
-- =============================================================================

local ns = "yt-player-search"

--- Setup custom highlight groups for search UI
function M.setup_highlights()
	ns = vim.api.nvim_create_namespace(ns)

	-- Get colorscheme-agnostic colors (fallback to catppuccin-like)
	local colors = {
		prompt = "#89b4fa", -- Blue
		input = "#cdd6f4", -- White
		mode = "#f9e2af", -- Yellow
		index = "#6c7086", -- Gray
		title = "#cdd6f4", -- White
		channel = "#a6adc8", -- Light gray
		duration = "#f38ba8", -- Red
		selected_bg = "#313244", -- Dark gray
		selected_fg = "#f5e0dc", -- Light
		playing = "#a6e3a1", -- Green
		loading = "#f9e2af", -- Yellow
		error = "#f38ba8", -- Red
		empty = "#6c7086", -- Gray
		footer = "#585b70", -- Dark gray
		hotkey = "#94e2d5", -- Teal
		border = "#45475a", -- Border
	}

	-- Try to detect user's colorscheme colors
	local ok, hl = pcall(vim.api.nvim_get_hl_by_name, "Normal", true)
	if ok and hl.foreground then
		colors.input = string.format("#%06x", hl.foreground)
		colors.title = colors.input
	end
	ok, hl = pcall(vim.api.nvim_get_hl_by_name, "Comment", true)
	if ok and hl.foreground then
		colors.channel = string.format("#%06x", hl.foreground)
		colors.footer = colors.channel
	end

	-- Define highlights with cterm ANSI fallbacks
	local highlights = {
		YTSearchPrompt = { fg = colors.prompt, ctermfg = 111, bold = true, cterm = { bold = true } },
		YTSearchInput = { fg = colors.input, ctermfg = 255 },
		YTSearchMode = { fg = colors.mode, ctermfg = 222, bold = true, cterm = { bold = true } },
		YTSearchIndex = { fg = "#7f849c", ctermfg = 244 },
		YTSearchTitle = { fg = colors.title, ctermfg = 255, bg = "None", bold = true, cterm = { bold = true } },
		YTSearchChannel = { fg = colors.channel, ctermfg = 248, bg = "None" },
		YTSearchDuration = { fg = colors.duration, ctermfg = 211 },
		YTSearchSelected = { fg = colors.selected_fg, ctermfg = 224, bg = colors.selected_bg, ctermbg = 237, bold = true, cterm = { bold = true } },
		YTSearchSelectedTitle = { fg = "#cba6f7", ctermfg = 183, bg = colors.selected_bg, ctermbg = 237, bold = true, cterm = { bold = true } },
		YTSearchSelectedMeta = { fg = "#a6adc8", ctermfg = 248, bg = colors.selected_bg, ctermbg = 237 },
		YTSearchSelectedDur = { fg = colors.duration, ctermfg = 211, bg = colors.selected_bg, ctermbg = 237, bold = true, cterm = { bold = true } },
		YTSearchAccent = { fg = "#cba6f7", ctermfg = 183, bg = colors.selected_bg, ctermbg = 237, bold = true, cterm = { bold = true } },
		YTSearchPlaying = { fg = colors.playing, ctermfg = 120, bold = true, cterm = { bold = true } },
		YTSearchPlayingTitle = { fg = colors.playing, ctermfg = 120, bold = true, cterm = { bold = true } },
		YTSearchPlayingMeta = { fg = colors.playing, ctermfg = 120 },
		YTSearchPlayingBadge = { fg = "#1e1e2e", ctermfg = 234, bg = colors.playing, ctermbg = 120, bold = true, cterm = { bold = true } },
		YTSearchLoading = { fg = colors.loading, ctermfg = 222, italic = true, cterm = { italic = true } },
		YTSearchError = { fg = colors.error, ctermfg = 211, bold = true, cterm = { bold = true } },
		YTSearchEmpty = { fg = colors.empty, ctermfg = 244, italic = true, cterm = { italic = true } },
		YTSearchFooter = { fg = colors.footer, ctermfg = 244 },
		YTSearchHotkey = { fg = colors.hotkey, ctermfg = 116, bold = true, cterm = { bold = true } },
		YTSearchBorder = { fg = colors.border, ctermfg = 239 },
		YTSearchSeparator = { fg = "#313244", ctermfg = 237 },
		YTSearchResultCount = { fg = colors.index, ctermfg = 244, italic = true, cterm = { italic = true } },
	}

	for name, opts in pairs(highlights) do
		vim.api.nvim_set_hl(0, name, opts)
	end
end

-- Auto-setup highlights when module loads
M.setup_highlights()

-- =============================================================================
-- SEARCH
-- =============================================================================

--- Search YouTube asynchronously using yt-dlp
--- Returns results via callback: list of { title, url, duration, channel, id }
---@param query string  Search query
---@param count number|nil  Number of results (default 10)
---@param offset number|nil  Number of results to skip (default 0)
---@param callback fun(results: table[], err: string|nil)
function M.search(query, count, offset, callback)
	count = count or 10
	-- Handle backward compatibility: if callback is nil but offset is a function,
	-- then the caller is using old signature: M.search(query, count, callback)
	if type(offset) == "function" then
		callback = offset
		offset = 0
	else
		offset = offset or 0
	end

	if vim.fn.executable("yt-dlp") == 0 then
		callback({}, "yt-dlp is not installed or not in PATH")
		return
	end

	local search_url = "ytsearchall:" .. query
	local args = {
		"yt-dlp",
		"--flat-playlist",
		"--dump-json",
		"--no-warnings",
		"--no-download",
		"--playlist-start",
		tostring(offset + 1),
		"--playlist-end",
		tostring(offset + count),
		search_url,
	}

	local stderr_chunks = {}
	local results = {}

	local stdout = uv.new_pipe(false)
	local stderr = uv.new_pipe(false)

	local handle
	handle = uv.spawn(args[1], {
		args = vim.list_slice(args, 2),
		stdio = { nil, stdout, stderr },
	}, function(code)
		-- Close all handles
		if stdout then
			pcall(function()
				stdout:read_stop()
				stdout:close()
			end)
		end
		if stderr then
			pcall(function()
				stderr:read_stop()
				stderr:close()
			end)
		end
		if handle then
			pcall(function()
				handle:close()
			end)
		end

		vim.schedule(function()
			if code ~= 0 then
				callback({}, table.concat(stderr_chunks, ""))
				return
			end

			callback(results, nil)
		end)
	end)

	if not handle then
		if stdout then
			pcall(function()
				stdout:close()
			end)
		end
		if stderr then
			pcall(function()
				stderr:close()
			end)
		end
		callback({}, "Failed to spawn yt-dlp")
		return
	end

	local partial_stdout = ""
	stdout:read_start(function(_, data)
		if data then
			partial_stdout = partial_stdout .. data
			local pos = 1
			while true do
				local newline = partial_stdout:find("\n", pos)
				if not newline then
					break
				end

				local line = partial_stdout:sub(pos, newline - 1)
				pos = newline + 1

				local ok, item = pcall(vim.json.decode, line)
				if ok and type(item) == "table" then
					local duration = 0
					if type(item.duration) == "number" then
						duration = item.duration
					elseif type(item.duration) == "string" then
						duration = tonumber(item.duration) or 0
					end

					results[#results + 1] = {
						title = type(item.title) == "string" and item.title or "Unknown",
						url = type(item.webpage_url) == "string" and item.webpage_url
							or (type(item.url) == "string" and item.url or ""),
						id = type(item.id) == "string" and item.id or "",
						duration = duration,
						channel = type(item.channel) == "string" and item.channel
							or (type(item.uploader) == "string" and item.uploader or ""),
						upload_date = type(item.upload_date) == "string" and item.upload_date
							or (type(item.release_date) == "string" and item.release_date or nil),
					}
				end
			end
			if pos > 1 then
				partial_stdout = partial_stdout:sub(pos)
			end
		end
	end)

	stderr:read_start(function(_, data)
		if data then
			stderr_chunks[#stderr_chunks + 1] = data
		end
	end)

	return handle
end

--- Fetch a full YouTube playlist and seamlessly append all tracks to the mpv queue
---@param url string  Playlist URL
function M.fetch_playlist(url)
	if vim.fn.executable("yt-dlp") == 0 then
		vim.notify("YT Control: yt-dlp is not installed", vim.log.levels.ERROR)
		return
	end

	local mpv = require("yt-player.mpv")
	local state_mod = require("yt-player.state")

	-- Make sure mpv is running first so we can queue to it
	if not mpv.is_running() then
		mpv.start()
	end

	vim.notify("YT Control: Fetching playlist...", vim.log.levels.INFO)

	local args = {
		"yt-dlp",
		"--flat-playlist",
		"--dump-json",
		"--no-warnings",
		url,
	}

	local stdout = uv.new_pipe(false)
	local handle

	handle = uv.spawn(args[1], {
		args = vim.list_slice(args, 2),
		stdio = { nil, stdout, nil },
	}, function(code)
		if stdout then
			pcall(function()
				stdout:read_stop()
				stdout:close()
			end)
		end
		if handle then
			pcall(function()
				handle:close()
			end)
		end

		vim.schedule(function()
			if code == 0 then
				vim.notify("YT Control: Finished queuing playlist!", vim.log.levels.INFO)
			else
				vim.notify("YT Control: Failed to fetch playlist", vim.log.levels.ERROR)
			end
		end)
	end)

	if not handle then
		if stdout then
			pcall(function()
				stdout:close()
			end)
		end
		return
	end

	local partial = ""
	local buffer_items = {}
	local processing_timer = uv.new_timer()

	processing_timer:start(
		500,
		500,
		vim.schedule_wrap(function()
			if #buffer_items > 0 then
				state_mod.current.playlist_meta = state_mod.current.playlist_meta or {}
				state_mod.current.artist_map = state_mod.current.artist_map or {}
				for _, item in ipairs(buffer_items) do
					state_mod.current.playlist_meta[item.url] = item.title
					if item.channel and item.channel ~= "" then
						state_mod.current.artist_map[item.url] = item.channel
					end
					mpv.send_command({ "loadfile", item.url, "append" })
				end
				buffer_items = {}
			end
		end)
	)

	stdout:read_start(function(_, data)
		if data then
			partial = partial .. data
			local pos = 1
			while true do
				local newline = partial:find("\n", pos)
				if not newline then
					break
				end

				local line = partial:sub(pos, newline - 1)
				pos = newline + 1

				local ok, item = pcall(vim.json.decode, line)
				if ok and type(item) == "table" then
					local item_url = type(item.webpage_url) == "string" and item.webpage_url
						or (type(item.url) == "string" and item.url or "")
					local item_title = type(item.title) == "string" and item.title or "Unknown"
					if item_url ~= "" then
						local item_channel = type(item.channel) == "string" and item.channel
							or (type(item.uploader) == "string" and item.uploader or "")
						table.insert(buffer_items, { url = item_url, title = item_title, channel = item_channel })
					end
				end
			end
			if pos > 1 then
				partial = partial:sub(pos)
			end
		else
			-- EOF
			pcall(function()
				processing_timer:stop()
				processing_timer:close()
			end)
			if #buffer_items > 0 then
				vim.schedule(function()
					state_mod.current.playlist_meta = state_mod.current.playlist_meta or {}
					state_mod.current.artist_map = state_mod.current.artist_map or {}
					for _, item in ipairs(buffer_items) do
						state_mod.current.playlist_meta[item.url] = item.title
						if item.channel and item.channel ~= "" then
							state_mod.current.artist_map[item.url] = item.channel
						end
						mpv.send_command({ "loadfile", item.url, "append" })
					end
					buffer_items = {}
				end)
			end
		end
	end)
end

--- Aliases for shared utilities
local fmt_duration = utils.format_duration
local safe_truncate = utils.safe_truncate
local pad_right = utils.pad_right

--- Open an interactive search window
---@param initial_query string|nil
function M.interactive_picker(initial_query)
	-- Layout configuration - 80% of screen
	local width = math.floor(vim.o.columns * 0.75)
	local total_height_raw = math.floor(vim.o.lines * 0.8)
	local search_height = 2 -- Search prompt area (prompt + separator)
	local help_height = 2 -- Fixed height for help text
	local LINES_PER_RESULT = 3
	local max_visible_layout = math.floor((total_height_raw - search_height - help_height) / LINES_PER_RESULT)
	local results_height = max_visible_layout * LINES_PER_RESULT
	local total_height = search_height + results_height + help_height
	local height = total_height
	local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
	local col = math.max(0, math.floor((vim.o.columns - width) / 2))

	-- Create buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"

	-- Open window
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " ♫ YouTube Search ",
		title_pos = "center",
	})

	-- Lock down all decorations
	vim.wo[win].cursorline = false
	vim.wo[win].cursorlineopt = "line"
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].wrap = false
	vim.wo[win].winblend = 0
	vim.wo[win].winhighlight = "Normal:NormalFloat"
	vim.wo[win].winfixheight = true -- Prevent window from resizing
	if vim.fn.has("nvim-0.9") == 1 then
		vim.wo[win].statuscolumn = ""
	end

	-- Re-measure actual width
	width = vim.api.nvim_win_get_width(win)

	-- Helper to dynamically update window title
	local function update_window_title(title_text)
		if win and vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_set_config, win, {
				title = " " .. title_text .. " ",
				title_pos = "center",
			})
		end
	end

	-- State
	local current_query = initial_query or ""
	local is_searching = false
	local results = {}
	local current_job = nil
	local spinner_idx = 0
	local selected_idx = 1
	local scroll_offset = 0
	local current_playing_url = nil
	local current_offset = 0
	local has_more = true
	local is_loading_more = false

	-- Layout constants
	local HEADER_LINES = 2 -- prompt + separator

	-- Prompt
	local prompt_prefix = " 🔍 "

	-- Initial buffer setup
	local function render_initial()
		local separator = string.rep("━", width)
		local lines = {
			prompt_prefix .. current_query,
			separator,
		}
		-- Pad to results_height lines
		for i = 1, results_height do
			table.insert(lines, "")
		end
		-- Pad to help_height lines (footer area)
		for i = 1, help_height do
			table.insert(lines, "")
		end
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

		vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPrompt", 0, 0, #prompt_prefix)
		vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSeparator", 1, 0, -1)
	end

	-- Build and render footer help text
	local function render_footer()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		local badges = {
			{ key = "j/k", desc = "Navigate" },
			{ key = "↵", desc = "Play" },
			{ key = "a", desc = "Queue" },
			{ key = "s", desc = "Save To Playlist" },
			{ key = "i", desc = "Search" },
		}
		if #results > 0 and has_more then
			table.insert(badges, { key = "L", desc = "Load More" })
		end
		table.insert(badges, { key = "q", desc = "Close" })

		local parts = {}
		for _, b in ipairs(badges) do
			table.insert(parts, string.format(" %s %s ", b.key, b.desc))
		end
		local help_text = "  " .. table.concat(parts, "  │  ")
		local sep = string.rep("─", width)

		-- Footer starts at line: search_height + results_height
		local footer_start = search_height + results_height

		-- Pad to help_height lines
		local lines = { sep, help_text }
		while #lines < help_height do
			table.insert(lines, "")
		end

		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, footer_start, footer_start + help_height, false, lines)

		vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSeparator", footer_start, 0, -1)
		vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchFooter", footer_start + 1, 0, -1)

		local offset = 2
		for _, b in ipairs(badges) do
			local badge_str = string.format(" %s %s ", b.key, b.desc)
			local key_str = " " .. b.key
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchHotkey", footer_start + 1, offset, offset + #key_str)
			offset = offset + #badge_str + 5
		end

		vim.bo[buf].modifiable = false
	end

	-- Render loading state with spinner
	local function render_loading(query)
		-- Don't render if not searching anymore
		if not is_searching then
			return
		end
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		update_window_title("🔍 Searching...")

		local spinners = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
		spinner_idx = (spinner_idx % #spinners) + 1
		local spinner = spinners[spinner_idx]

		local text = string.format(" %s Searching for '%s'...", spinner, query or "...")
		local line_count = vim.api.nvim_buf_line_count(buf)

		-- Clear results area and show loading
		vim.bo[buf].modifiable = true
		if line_count > HEADER_LINES then
			vim.api.nvim_buf_set_lines(buf, HEADER_LINES, -1, false, {})
		end
		vim.api.nvim_buf_set_lines(buf, HEADER_LINES, HEADER_LINES + 1, false, { text })
		vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchLoading", HEADER_LINES, 0, -1)
		vim.bo[buf].modifiable = false

		-- Schedule next frame
		if is_searching then
			vim.defer_fn(function()
				render_loading(query)
			end, 80)
		end
	end

	-- Render results to main buffer
	local function render_results()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		local display = {}

		-- Limit to what fits in visible area
		local max_visible = math.floor(results_height / LINES_PER_RESULT)
		local start_idx = scroll_offset + 1
		local end_idx = math.min(#results, scroll_offset + max_visible)

		for i = start_idx, end_idx do
			local r = results[i]
			local is_selected = (i == selected_idx)
			local is_playing = (r.url == current_playing_url)

			local dur = fmt_duration(r.duration)
			local accent = is_playing and " ♫" or (is_selected and " ❯" or "  ")
			local idx_str = string.format("%2d", i)

			local prefix_width = vim.fn.strdisplaywidth(accent) + 1 + vim.fn.strdisplaywidth(idx_str) + 2
			local title_max = width - prefix_width - 1
			local title_text = safe_truncate(r.title, title_max)
			local title_line = accent .. " " .. idx_str .. ". " .. title_text

			local indent = string.rep(" ", vim.fn.strdisplaywidth(accent) + 1 + vim.fn.strdisplaywidth(idx_str) + 2)
			local channel = r.channel and r.channel ~= "" and (r.channel:gsub("[\n\r]", " ")) or ""

			-- Format upload date (e.g. YYYYMMDD -> YYYY-MM-DD)
			local upload_date_formatted = nil
			if r.upload_date and type(r.upload_date) == "string" and #r.upload_date == 8 then
				local y = r.upload_date:sub(1, 4)
				local m = r.upload_date:sub(5, 6)
				local d = r.upload_date:sub(7, 8)
				upload_date_formatted = string.format("%s-%s-%s", y, m, d)
			end

			local meta_parts = {}
			if channel ~= "" then
				table.insert(meta_parts, "📺 " .. channel)
			end
			if dur ~= "" then
				table.insert(meta_parts, "⏱ " .. dur)
			end
			if upload_date_formatted then
				table.insert(meta_parts, "📅 " .. upload_date_formatted)
			end
			if is_playing then
				table.insert(meta_parts, "♫ Now Playing")
			end

			local meta_line = indent .. table.concat(meta_parts, "  ·  ")

			table.insert(display, title_line)
			table.insert(display, meta_line)
			if i < end_idx then
				table.insert(display, "  " .. string.rep("─", width - 4))
			end
		end

		-- Ensure we have exactly results_height lines
		while #display < results_height do
			table.insert(display, string.rep(" ", width))
		end
		while #display > results_height do
			display[#display] = nil
		end

		-- Loading more indicator
		if is_loading_more then
			local spinners = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
			spinner_idx = (spinner_idx % #spinners) + 1
			local spinner = spinners[spinner_idx]

			local load_text = string.format("  %s Loading more results...", spinner)
			local lw = vim.fn.strdisplaywidth(load_text)
			if lw < width then
				load_text = load_text .. string.rep(" ", width - lw)
			end
			display[#display] = load_text
		end

		-- Pad all lines to full width
		for idx, line in ipairs(display) do
			local lw = vim.fn.strdisplaywidth(line)
			if lw < width then
				display[idx] = line .. string.rep(" ", width - lw)
			end
		end

		-- Write to buffer (start at line 2, after prompt + separator)
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, HEADER_LINES, -1, false, display)

		-- Clear old highlights in results area
		vim.api.nvim_buf_clear_namespace(buf, ns, HEADER_LINES, -1)

		-- Highlight ALL displayed results
		for i = start_idx, end_idx do
			local r = results[i]
			local display_idx = i - scroll_offset
			local title_ln = HEADER_LINES + (display_idx - 1) * LINES_PER_RESULT
			local meta_ln = title_ln + 1

			local is_selected = (i == selected_idx)
			local is_playing = (r.url == current_playing_url)

			local accent_byte_len = (is_playing or is_selected) and 4 or 2

			if is_playing then
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlaying", title_ln, 0, accent_byte_len)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlayingTitle", title_ln, accent_byte_len, -1)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlayingMeta", meta_ln, 0, -1)
			elseif is_selected then
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchAccent", title_ln, 0, accent_byte_len)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSelectedTitle", title_ln, accent_byte_len, -1)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchAccent", meta_ln, 0, accent_byte_len)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSelectedMeta", meta_ln, 0, -1)

				local meta_lines = vim.api.nvim_buf_get_lines(buf, meta_ln, meta_ln + 1, false)
				local meta_content = meta_lines[1] or ""
				local dur = fmt_duration(r.duration)
				if dur ~= "" then
					local dur_byte_start = meta_content:find(dur, 1, true)
					if dur_byte_start then
						vim.api.nvim_buf_add_highlight(
							buf,
							ns,
							"YTSearchSelectedDur",
							meta_ln,
							dur_byte_start - 1,
							dur_byte_start - 1 + #dur
						)
					end
				end
			else
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchIndex", title_ln, 0, accent_byte_len + 5)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchTitle", title_ln, accent_byte_len + 5, -1)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchChannel", meta_ln, 0, -1)

				local meta_lines = vim.api.nvim_buf_get_lines(buf, meta_ln, meta_ln + 1, false)
				local meta_content = meta_lines[1] or ""
				local dur = fmt_duration(r.duration)
				if dur ~= "" then
					local dur_byte_start = meta_content:find(dur, 1, true)
					if dur_byte_start then
						vim.api.nvim_buf_add_highlight(
							buf,
							ns,
							"YTSearchDuration",
							meta_ln,
							dur_byte_start - 1,
							dur_byte_start - 1 + #dur
						)
					end
				end
			end

			if i < end_idx then
				local sep_ln = meta_ln + 1
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSeparator", sep_ln, 0, -1)
			end
		end

		if is_loading_more then
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchLoading", HEADER_LINES + results_height - 1, 0, -1)
		end

		vim.bo[buf].modifiable = false

		-- Update window title dynamically to show count
		if not is_loading_more then
			update_window_title("♫ YouTube Search (" .. #results .. ")")
		end

		-- Update footer
		render_footer()

		-- Schedule next frame for spinner
		if is_loading_more then
			vim.defer_fn(function()
				render_results()
			end, 80)
		end
	end

	-- Load more results
	local function load_more()
		if not has_more or is_loading_more or is_searching then
			return
		end
		if #results == 0 then
			return
		end
		is_loading_more = true
		update_window_title("♫ YouTube Search (" .. #results .. "+)")
		local limit = require("yt-player").config.search.limit or 10
		render_results() -- Update UI to show loading indicator
		current_job = M.search(current_query, limit, current_offset, function(new_results, err)
			is_loading_more = false
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			if err then
				vim.notify("YT Control: Load more failed - " .. err, vim.log.levels.ERROR)
				render_results()
				return
			end
			if #new_results == 0 then
				has_more = false
				vim.notify("YT Control: No more results", vim.log.levels.INFO)
				render_results()
				return
			end
			-- Append new results
			for _, r in ipairs(new_results) do
				table.insert(results, r)
			end
			current_offset = current_offset + #new_results
			-- Check if we got less than limit, meaning no more results
			if #new_results < limit then
				has_more = false
			end
			render_results()
		end)
	end

	-- Jump to search input
	local function enter_search_mode()
		vim.bo[buf].modifiable = true
		vim.api.nvim_win_set_cursor(win, { 1, #prompt_prefix })
		vim.cmd("startinsert!")
	end

	-- Perform search
	local function do_search()
		-- Get the raw line from buffer first
		local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
		local line = lines[1] or ""

		-- Extract query robustly by ignoring the exact magnifying glass character instead
		local query = line:gsub("🔍", "")
		query = vim.trim(query)

		-- Guard: don't search for empty/nil
		if not query or query == "" then
			return
		end

		current_query = query
		is_searching = true
		results = {}
		selected_idx = 1
		scroll_offset = 0
		current_offset = 0
		has_more = true
		is_loading_more = false

		-- Start spinner animation
		spinner_idx = 0
		render_loading(query)
		vim.cmd("stopinsert")

		local limit = require("yt-player").config.search.limit or 10

		-- Kill previous job
		if current_job and not current_job:is_closing() then
			pcall(function()
				current_job:kill(15)
			end)
		end

		current_job = M.search(current_query, limit, 0, function(res, err)
			current_job = nil
			is_searching = false

			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end

			if err then
				update_window_title("❌ Search Error")
				vim.bo[buf].modifiable = true
				vim.api.nvim_buf_set_lines(buf, HEADER_LINES, -1, false, { "  Error: " .. err })
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchError", HEADER_LINES, 0, -1)
				vim.bo[buf].modifiable = false
				return
			end

			if #res == 0 then
				update_window_title("🔍 No Results")
				vim.bo[buf].modifiable = true
				vim.api.nvim_buf_set_lines(buf, HEADER_LINES, -1, false, { "  No results found." })
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchEmpty", HEADER_LINES, 0, -1)
				vim.bo[buf].modifiable = false
				return
			end

			results = res
			selected_idx = 1
			scroll_offset = 0
			current_offset = #res
			render_results()

			-- Jump to first result
			vim.api.nvim_win_set_cursor(win, { HEADER_LINES + 1, 0 })
		end)
	end

	-- Get current result based on cursor position
	local function get_current_result()
		local r = vim.api.nvim_win_get_cursor(win)[1]
		local display_idx = math.floor((r - HEADER_LINES - 1) / LINES_PER_RESULT) + 1
		local result_idx = display_idx + scroll_offset
		if result_idx < 1 or result_idx > #results then
			return nil
		end
		return results[result_idx]
	end

	-- Jump to specific result index
	local function jump_to_index(idx)
		if #results == 0 then
			return
		end
		local old_idx = selected_idx
		local old_scroll = scroll_offset
		selected_idx = math.max(1, math.min(#results, idx))
		local max_visible = math.floor(results_height / LINES_PER_RESULT)
		if selected_idx > scroll_offset + max_visible then
			scroll_offset = selected_idx - max_visible
		elseif selected_idx <= scroll_offset then
			scroll_offset = selected_idx - 1
		end
		if old_scroll ~= scroll_offset then
			render_results()
		elseif old_idx ~= selected_idx then
			update_selection(old_idx, selected_idx)
		end
		local target_line = HEADER_LINES + 1 + (selected_idx - scroll_offset - 1) * LINES_PER_RESULT
		vim.api.nvim_win_set_cursor(win, { target_line, 0 })
	end

	-- Lightweight highlight and accent update for single row
	local function render_row_highlights(idx)
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end
		local max_visible = math.floor(results_height / LINES_PER_RESULT)
		local start_idx = scroll_offset + 1
		local end_idx = math.min(#results, scroll_offset + max_visible)
		if idx < start_idx or idx > end_idx then
			return
		end

		local r = results[idx]
		if not r then
			return
		end

		local display_idx = idx - scroll_offset
		local title_ln = HEADER_LINES + (display_idx - 1) * LINES_PER_RESULT
		local meta_ln = title_ln + 1

		local is_selected = (idx == selected_idx)
		local is_playing = (r.url == current_playing_url)
		local new_accent = is_playing and " ♫" or (is_selected and " ❯" or "  ")

		local lines = vim.api.nvim_buf_get_lines(buf, title_ln, title_ln + 1, false)
		local line_text = lines[1] or ""
		local old_accent_len = (line_text:sub(1, 4) == " ♫" or line_text:sub(1, 4) == " ❯") and 4 or 2

		vim.bo[buf].modifiable = true
		pcall(vim.api.nvim_buf_set_text, buf, title_ln, 0, title_ln, old_accent_len, { new_accent })
		vim.bo[buf].modifiable = false

		vim.api.nvim_buf_clear_namespace(buf, ns, title_ln, meta_ln + 1)

		local accent_byte_len = (is_playing or is_selected) and 4 or 2
		if is_playing then
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlaying", title_ln, 0, accent_byte_len)
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlayingTitle", title_ln, accent_byte_len, -1)
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlayingMeta", meta_ln, 0, -1)
		elseif is_selected then
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchAccent", title_ln, 0, accent_byte_len)
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSelectedTitle", title_ln, accent_byte_len, -1)
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchAccent", meta_ln, 0, accent_byte_len)
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSelectedMeta", meta_ln, 0, -1)

			local meta_lines = vim.api.nvim_buf_get_lines(buf, meta_ln, meta_ln + 1, false)
			local meta_content = meta_lines[1] or ""
			local dur = fmt_duration(r.duration)
			if dur ~= "" then
				local dur_byte_start = meta_content:find(dur, 1, true)
				if dur_byte_start then
					vim.api.nvim_buf_add_highlight(
						buf,
						ns,
						"YTSearchSelectedDur",
						meta_ln,
						dur_byte_start - 1,
						dur_byte_start - 1 + #dur
					)
				end
			end
		else
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchIndex", title_ln, 0, accent_byte_len + 5)
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchTitle", title_ln, accent_byte_len + 5, -1)
			vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchChannel", meta_ln, 0, -1)

			local meta_lines = vim.api.nvim_buf_get_lines(buf, meta_ln, meta_ln + 1, false)
			local meta_content = meta_lines[1] or ""
			local dur = fmt_duration(r.duration)
			if dur ~= "" then
				local dur_byte_start = meta_content:find(dur, 1, true)
				if dur_byte_start then
					vim.api.nvim_buf_add_highlight(
						buf,
						ns,
						"YTSearchDuration",
						meta_ln,
						dur_byte_start - 1,
						dur_byte_start - 1 + #dur
					)
				end
			end
		end
	end

	local function update_selection(old_idx, new_idx)
		render_row_highlights(old_idx)
		render_row_highlights(new_idx)
	end

	-- Navigation - through all results
	local function jump(dir)
		if vim.fn.mode() == "i" then
			vim.cmd("stopinsert")
		end
		if #results == 0 then
			return
		end

		local old_idx = selected_idx
		local old_scroll = scroll_offset
		selected_idx = math.max(1, math.min(#results, selected_idx + dir))

		local max_visible = math.floor(results_height / LINES_PER_RESULT)
		if selected_idx > scroll_offset + max_visible then
			scroll_offset = selected_idx - max_visible
		elseif selected_idx <= scroll_offset then
			scroll_offset = selected_idx - 1
		end

		if old_idx ~= selected_idx then
			if old_scroll ~= scroll_offset then
				render_results()
			else
				update_selection(old_idx, selected_idx)
			end
			local target_line = HEADER_LINES + 1 + (selected_idx - scroll_offset - 1) * LINES_PER_RESULT
			vim.api.nvim_win_set_cursor(win, { target_line, 0 })
		end
	end

	-- Play current result
	local function play_result()
		if vim.fn.mode() == "i" then
			vim.cmd("stopinsert")
		end
		local res = get_current_result()
		if res and res.url ~= "" then
			current_playing_url = res.url -- Track this as playing
			require("yt-player").load(res.url)
			vim.notify("YT Control: Playing -> " .. res.title, vim.log.levels.INFO)
			render_results() -- Update playing indicator
		end
	end

	-- Append to queue
	local function append_result()
		if vim.fn.mode() == "i" then
			vim.cmd("stopinsert")
		end
		local res = get_current_result()
		if res and res.url ~= "" then
			current_playing_url = res.url
			require("yt-player").queue(res)
			render_results() -- Update playing indicator
		end
	end

	-- Setup keymaps
	local opts = { buffer = buf, silent = true }

	-- Enter to search (line 1) or play (results)
	vim.keymap.set({ "i", "n" }, "<CR>", function()
		local r = vim.api.nvim_win_get_cursor(win)[1]
		if r == 1 then
			if not is_searching then
				do_search()
			end
		else
			play_result()
		end
	end, opts)

	-- Queue with a/A or C-a
	vim.keymap.set({ "i", "n" }, "<C-a>", function()
		local r = vim.api.nvim_win_get_cursor(win)[1]
		if r > 1 then
			append_result()
		end
	end, opts)
	vim.keymap.set("n", "A", append_result, opts)
	vim.keymap.set("n", "a", append_result, opts)

	-- Save (s)
	vim.keymap.set("n", "s", function()
		if vim.fn.mode() == "i" then
			vim.cmd("stopinsert")
		end
		local r = get_current_result()
		if r then
			require("yt-player.playlists").prompt_save(r)
		end
	end, opts)

	-- Navigation
	vim.keymap.set("n", "j", function()
		jump(1)
	end, opts)
	vim.keymap.set("n", "k", function()
		jump(-1)
	end, opts)
	vim.keymap.set({ "n", "i" }, "<Down>", function()
		jump(1)
	end, opts)
	vim.keymap.set({ "n", "i" }, "<Up>", function()
		jump(-1)
	end, opts)
	vim.keymap.set("n", "<Tab>", function()
		jump(1)
	end, opts)
	vim.keymap.set("n", "<S-Tab>", function()
		jump(-1)
	end, opts)
	vim.keymap.set("i", "<Tab>", function()
		vim.cmd("stopinsert")
		jump(1)
	end, opts)

	-- First/last
	vim.keymap.set("n", "gg", function()
		jump_to_index(1)
	end, opts) -- first
	vim.keymap.set("n", "G", function()
		jump_to_index(#results)
	end, opts) -- last

	-- Alternative navigation in insert mode
	vim.keymap.set("i", "<C-j>", function()
		jump(1)
	end, opts)
	vim.keymap.set("i", "<C-k>", function()
		jump(-1)
	end, opts)

	-- Load more results
	vim.keymap.set("n", "L", load_more, opts)

	-- Prevent editing the prompt prefix
	local function lock_prompt()
		local cursor = vim.api.nvim_win_get_cursor(win)
		if cursor[1] == 1 and cursor[2] < #prompt_prefix then
			vim.api.nvim_win_set_cursor(win, { 1, #prompt_prefix })
		end
	end

	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		buffer = buf,
		callback = lock_prompt,
	})

	vim.keymap.set("i", "<BS>", function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		if cursor[1] == 1 and cursor[2] <= #prompt_prefix then
			return ""
		end
		return "<BS>"
	end, { buffer = buf, expr = true })

	vim.keymap.set("i", "<C-u>", function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		if cursor[1] == 1 and cursor[2] > #prompt_prefix then
			return string.rep("<BS>", cursor[2] - #prompt_prefix)
		elseif cursor[1] == 1 then
			return ""
		end
		return "<C-u>"
	end, { buffer = buf, expr = true })

	vim.keymap.set("i", "<C-w>", function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		if cursor[1] == 1 and cursor[2] <= #prompt_prefix then
			return ""
		end
		return "<C-w>"
	end, { buffer = buf, expr = true })

	vim.keymap.set("i", "<Left>", function()
		local cursor = vim.api.nvim_win_get_cursor(win)
		if cursor[1] == 1 and cursor[2] <= #prompt_prefix then
			return ""
		end
		return "<Left>"
	end, { buffer = buf, expr = true })

	-- Search (new query) - press i to edit search
	vim.keymap.set("n", "i", enter_search_mode, opts)

	-- Escape: close if on first line, otherwise go to search
	vim.keymap.set("n", "<Esc>", function()
		local r = vim.api.nvim_win_get_cursor(win)[1]
		if r == 1 then
			is_searching = false
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		else
			enter_search_mode()
		end
	end, opts)

	-- Close with q
	vim.keymap.set("n", "q", function()
		is_searching = false
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end, opts)

	-- Initialize UI
	render_initial()
	render_results() -- This will render footer (and results if any)

	if initial_query and initial_query ~= "" then
		do_search()
	else
		vim.bo[buf].modifiable = true
		vim.api.nvim_win_set_cursor(win, { 1, #prompt_prefix })
		vim.cmd("startinsert!")
	end

	-- Lock buffer when leaving insert mode
	vim.api.nvim_create_autocmd("InsertLeave", {
		buffer = buf,
		callback = function()
			if vim.api.nvim_buf_is_valid(buf) then
				vim.bo[buf].modifiable = false
			end
		end,
	})

	-- Cleanup on close
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			is_searching = false
			if current_job and not current_job:is_closing() then
				pcall(function()
					current_job:kill(15)
				end)
			end
		end,
	})
end

return M
