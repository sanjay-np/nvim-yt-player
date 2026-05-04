---@mod yt-player.search YouTube search via yt-dlp
local M = {}

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

	-- Define highlights
	local highlights = {
		YTSearchPrompt = { fg = colors.prompt, bold = true },
		YTSearchInput = { fg = colors.input },
		YTSearchMode = { fg = colors.mode, bold = true },
		YTSearchIndex = { fg = "#7f849c" },
		YTSearchTitle = { fg = colors.title, bg = "None", bold = true },
		YTSearchChannel = { fg = colors.channel, bg = "None" },
		YTSearchDuration = { fg = colors.duration },
		YTSearchSelected = { fg = colors.selected_fg, bg = colors.selected_bg, bold = true },
		YTSearchSelectedTitle = { fg = "#cba6f7", bg = colors.selected_bg, bold = true },
		YTSearchSelectedMeta = { fg = "#a6adc8", bg = colors.selected_bg },
		YTSearchSelectedDur = { fg = colors.duration, bg = colors.selected_bg, bold = true },
		YTSearchAccent = { fg = "#cba6f7", bg = colors.selected_bg, bold = true },
		YTSearchPlaying = { fg = colors.playing, bold = true },
		YTSearchPlayingTitle = { fg = colors.playing, bold = true },
		YTSearchPlayingMeta = { fg = colors.playing },
		YTSearchPlayingBadge = { fg = "#1e1e2e", bg = colors.playing, bold = true },
		YTSearchLoading = { fg = colors.loading, italic = true },
		YTSearchError = { fg = colors.error, bold = true },
		YTSearchEmpty = { fg = colors.empty, italic = true },
		YTSearchFooter = { fg = colors.footer },
		YTSearchHotkey = { fg = colors.hotkey, bold = true },
		YTSearchBorder = { fg = colors.border },
		YTSearchSeparator = { fg = "#313244" },
		YTSearchResultCount = { fg = colors.index, italic = true },
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

	local stdout = vim.loop.new_pipe(false)
	local stderr = vim.loop.new_pipe(false)

	local handle
	handle = vim.loop.spawn(args[1], {
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

	local stdout = vim.loop.new_pipe(false)
	local handle

	handle = vim.loop.spawn(args[1], {
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
	local processing_timer = (vim.uv or vim.loop).new_timer()

	processing_timer:start(
		500,
		500,
		vim.schedule_wrap(function()
			if #buffer_items > 0 then
				state_mod.current.playlist_meta = state_mod.current.playlist_meta or {}
				for _, item in ipairs(buffer_items) do
					state_mod.current.playlist_meta[item.url] = item.title
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
						table.insert(buffer_items, { url = item_url, title = item_title })
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
					for _, item in ipairs(buffer_items) do
						state_mod.current.playlist_meta[item.url] = item.title
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
			local accent = is_playing and " ▶" or (is_selected and " ▎" or "  ")
			local idx_str = string.format("%2d", i)

			local prefix_width = vim.fn.strdisplaywidth(accent) + 1 + vim.fn.strdisplaywidth(idx_str) + 2
			local title_max = width - prefix_width - 1
			local title_text = safe_truncate(r.title, title_max)
			local title_line = accent .. " " .. idx_str .. ". " .. title_text

			local indent = string.rep(" ", vim.fn.strdisplaywidth(accent) + 1 + vim.fn.strdisplaywidth(idx_str) + 2)
			local channel = r.channel and r.channel ~= "" and (r.channel:gsub("[\n\r]", " ")) or ""

			local meta_parts = {}
			if channel ~= "" then
				table.insert(meta_parts, channel)
			end
			if dur ~= "" then
				table.insert(meta_parts, dur)
			end
			if is_playing then
				table.insert(meta_parts, "♫ Now Playing")
			end

			local meta_line = indent .. table.concat(meta_parts, "  ·  ")

			table.insert(display, title_line)
			table.insert(display, meta_line)
			if i < end_idx then
				table.insert(display, "")
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

			local accent_byte_len = is_playing and #" ▶" or (is_selected and #" ▎" or 2)

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
				vim.bo[buf].modifiable = true
				vim.api.nvim_buf_set_lines(buf, HEADER_LINES, -1, false, { "  Error: " .. err })
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchError", HEADER_LINES, 0, -1)
				vim.bo[buf].modifiable = false
				return
			end

			if #res == 0 then
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
		selected_idx = math.max(1, math.min(#results, idx))
		local max_visible = math.floor(results_height / LINES_PER_RESULT)
		if selected_idx > scroll_offset + max_visible then
			scroll_offset = selected_idx - max_visible
		elseif selected_idx <= scroll_offset then
			scroll_offset = selected_idx - 1
		end
		render_results()
		local target_line = HEADER_LINES + 1 + (selected_idx - scroll_offset - 1) * LINES_PER_RESULT
		vim.api.nvim_win_set_cursor(win, { target_line, 0 })
	end

	-- Lightweight highlight update for selection changes only
	local function update_selection_highlights()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		-- Clear old selection highlights (lines 2 onward)
		vim.api.nvim_buf_clear_namespace(buf, ns, 2, -1)

		-- Reapply highlights for all results
		for i, r in ipairs(results) do
			local title_ln = 2 + (i - 1) * LINES_PER_RESULT
			local meta_ln = title_ln + 1
			local sep_ln = title_ln + 2
			local is_selected = (i == selected_idx)
			local is_playing = (r.url == current_playing_url)

			local accent_byte_len = is_playing and #" ▶" or (is_selected and #" ▎" or 2)

			if is_playing then
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlaying", title_ln, 0, accent_byte_len)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlayingTitle", title_ln, accent_byte_len, -1)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlayingMeta", meta_ln, 0, -1)
			elseif is_selected then
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchAccent", title_ln, 0, accent_byte_len)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSelectedTitle", title_ln, accent_byte_len, -1)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchAccent", meta_ln, 0, accent_byte_len)
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSelectedMeta", meta_ln, 0, -1)

				-- Duration highlight
				local lines = vim.api.nvim_buf_get_lines(buf, meta_ln, meta_ln + 1, false)
				local meta_content = lines[1] or ""
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

				-- Duration highlight
				local lines = vim.api.nvim_buf_get_lines(buf, meta_ln, meta_ln + 1, false)
				local meta_content = lines[1] or ""
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

			if i < #results then
				vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSeparator", sep_ln, 0, -1)
			end
		end
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
		selected_idx = math.max(1, math.min(#results, selected_idx + dir))

		local max_visible = math.floor(results_height / LINES_PER_RESULT)
		if selected_idx > scroll_offset + max_visible then
			scroll_offset = selected_idx - max_visible
		elseif selected_idx <= scroll_offset then
			scroll_offset = selected_idx - 1
		end

		if old_idx ~= selected_idx then
			render_results()
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
	vim.keymap.set("n", "g", function()
		jump_to_index(#results)
	end, opts) -- last
	vim.keymap.set("n", "G", function()
		jump_to_index(1)
	end, opts) -- first

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
