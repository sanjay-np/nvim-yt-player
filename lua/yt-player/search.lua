---@mod yt-player.search YouTube search via yt-dlp and modern picker
local M = {}

local uv = vim.uv or vim.loop
local utils = require("yt-player.utils")
local theme = require("yt-player.ui.theme")
local window = require("yt-player.ui.window")
local state_mod = require("yt-player.state")

local LINES_PER_RESULT = 3

-- =============================================================================
-- HIGHLIGHTS
-- =============================================================================

function M.setup_highlights()
	theme.setup_highlights()
end

-- =============================================================================
-- SEARCH CORE LOGIC
-- =============================================================================

--- Search YouTube asynchronously using yt-dlp
--- Returns results via callback: list of { title, url, duration, channel, id, upload_date }
---@param query string  Search query
---@param count number|nil  Number of results (default 10)
---@param offset number|nil  Number of results to skip (default 0)
---@param callback fun(results: table[], err: string|nil)
function M.search(query, count, offset, callback)
	count = count or 10
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
			pcall(function() stdout:close() end)
		end
		if stderr then
			pcall(function() stderr:close() end)
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
					local item_url = type(item.webpage_url) == "string" and item.webpage_url
						or (type(item.url) == "string" and item.url or "")
					local item_title = type(item.title) == "string" and item.title or "Unknown"

					if item_url ~= "" then
						local dur = tonumber(item.duration) or 0
						local ch = type(item.channel) == "string" and item.channel
							or (type(item.uploader) == "string" and item.uploader or "")
						local item_id = type(item.id) == "string" and item.id or ""
						local upload_date = type(item.upload_date) == "string" and item.upload_date
							or (type(item.release_date) == "string" and item.release_date or nil)

						table.insert(results, {
							title = item_title,
							url = item_url,
							duration = dur,
							channel = ch,
							id = item_id,
							upload_date = upload_date,
						})
					end
				end
			end
			if pos > 1 then
				partial_stdout = partial_stdout:sub(pos)
			end
		end
	end)

	stderr:read_start(function(_, data)
		if data then
			table.insert(stderr_chunks, data)
		end
	end)

	return handle
end

--- Fetch a full YouTube playlist and append all tracks to mpv queue
---@param url string  Playlist URL
function M.fetch_playlist(url)
	if vim.fn.executable("yt-dlp") == 0 then
		vim.notify("YT Control: yt-dlp is not installed", vim.log.levels.ERROR)
		return
	end

	local mpv = require("yt-player.mpv")
	local state_module = state_mod

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
			pcall(function() handle:close() end)
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
			pcall(function() stdout:close() end)
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
				state_module.current.playlist_meta = state_module.current.playlist_meta or {}
				state_module.current.artist_map = state_module.current.artist_map or {}
				for _, item in ipairs(buffer_items) do
					state_module.current.playlist_meta[item.url] = item.title
					if item.channel and item.channel ~= "" then
						state_module.current.artist_map[item.url] = item.channel
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
			pcall(function()
				processing_timer:stop()
				processing_timer:close()
			end)
			if #buffer_items > 0 then
				vim.schedule(function()
					state_module.current.playlist_meta = state_module.current.playlist_meta or {}
					state_module.current.artist_map = state_module.current.artist_map or {}
					for _, item in ipairs(buffer_items) do
						state_module.current.playlist_meta[item.url] = item.title
						if item.channel and item.channel ~= "" then
							state_module.current.artist_map[item.url] = item.channel
						end
						mpv.send_command({ "loadfile", item.url, "append" })
					end
					buffer_items = {}
				end)
			end
		end
	end)
end

-- =============================================================================
-- REDESIGNED MULTI-PANE SEARCH PICKER
-- =============================================================================

--- Open modern multi-pane search picker
---@param initial_query string|nil
function M.interactive_picker(initial_query)
	local total_w = math.floor(vim.o.columns * 0.84)
	local total_h = math.floor(vim.o.lines * 0.78)
	local row = math.max(0, math.floor((vim.o.lines - total_h) / 2))
	local col = math.max(0, math.floor((vim.o.columns - total_w) / 2))

	local prompt_h = 1
	local body_h = total_h - prompt_h - 3
	local results_w = math.floor(total_w * 0.58)
	local preview_w = total_w - results_w - 2

	-- Buffers
	local prompt_buf = vim.api.nvim_create_buf(false, true)
	local results_buf = vim.api.nvim_create_buf(false, true)
	local preview_buf = vim.api.nvim_create_buf(false, true)

	for _, b in ipairs({ prompt_buf, results_buf, preview_buf }) do
		vim.bo[b].buftype = "nofile"
		vim.bo[b].bufhidden = "wipe"
		vim.bo[b].swapfile = false
	end

	local winhl = "Normal:YtPlayerNormal,NormalNC:YtPlayerNormal,NormalFloat:YtPlayerNormal,FloatBorder:YtPlayerBorder,FloatTitle:YtPlayerTitle,FloatFooter:YtPlayerFooter,CursorLine:YtPlayerSelected"

	-- 1. Prompt Window
	local prompt_win = vim.api.nvim_open_win(prompt_buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = total_w,
		height = prompt_h,
		style = "minimal",
		border = "rounded",
		title = string.format(" %s Search YouTube ", theme.icon("search")),
		title_pos = "center",
		footer = " [↵] Search  [↓/Tab] Results  [Esc] Close ",
		footer_pos = "center",
	})

	-- 2. Results Window
	local results_win = vim.api.nvim_open_win(results_buf, false, {
		relative = "editor",
		row = row + prompt_h + 2,
		col = col,
		width = results_w,
		height = body_h,
		style = "minimal",
		border = "rounded",
		title = " Results ",
		title_pos = "center",
		footer = " [↵] Play  [a] Queue  [s] Save  [L] Load More ",
		footer_pos = "center",
	})

	-- 3. Preview Window
	local preview_win = vim.api.nvim_open_win(preview_buf, false, {
		relative = "editor",
		row = row + prompt_h + 2,
		col = col + results_w + 2,
		width = preview_w,
		height = body_h,
		style = "minimal",
		border = "rounded",
		title = " Track Details ",
		title_pos = "center",
	})

	for _, w in ipairs({ prompt_win, results_win, preview_win }) do
		vim.wo[w].winhighlight = winhl
		vim.wo[w].number = false
		vim.wo[w].relativenumber = false
		vim.wo[w].signcolumn = "no"
	end
	vim.wo[results_win].cursorline = true

	local state = {
		query = initial_query or "",
		results = {},
		selected_idx = 1,
		is_searching = false,
		is_loading_more = false,
		has_more = true,
		offset = 0,
		job = nil,
		current_playing_url = nil,
	}

	-- Animated Spinner
	local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
	local spinner_idx = 1
	local spinner_timer = nil

	local function stop_spinner()
		if spinner_timer then
			pcall(function()
				spinner_timer:stop()
				spinner_timer:close()
			end)
			spinner_timer = nil
		end
	end

	local function start_spinner(msg)
		stop_spinner()
		spinner_timer = uv.new_timer()
		spinner_timer:start(0, 80, vim.schedule_wrap(function()
			if not vim.api.nvim_buf_is_valid(results_buf) then
				stop_spinner()
				return
			end
			spinner_idx = (spinner_idx % #spinner_frames) + 1
			local sp = spinner_frames[spinner_idx]
			local lines = {
				"",
				string.format("   %s %s", sp, msg),
				"   Please wait while yt-dlp fetches streams...",
			}
			local hls = {
				{ line = 1, hl = "YtPlayerAccent", col_start = 0, col_end = -1 },
				{ line = 2, hl = "YtPlayerMuted", col_start = 0, col_end = -1 },
			}
			window.render(results_buf, lines, hls)
			if vim.api.nvim_win_is_valid(results_win) then
				pcall(vim.api.nvim_win_set_config, results_win, {
					title = string.format(" %s Searching... ", sp),
					title_pos = "center",
				})
			end
		end))
	end

	local function close_all()
		stop_spinner()
		if state.job and not state.job:is_closing() then
			pcall(function() state.job:kill(15) end)
		end
		window.safe_close(prompt_win, prompt_buf)
		window.safe_close(results_win, results_buf)
		window.safe_close(preview_win, preview_buf)
	end

	-- Render Track Details Preview Pane
	local function render_preview()
		if not vim.api.nvim_buf_is_valid(preview_buf) then
			return
		end

		local item = state.results[state.selected_idx]
		local lines = {}
		local hls = {}

		if not item then
			table.insert(lines, "")
			table.insert(lines, "   Select a result to view details")
			table.insert(hls, { line = 1, hl = "YtPlayerMuted", col_start = 0, col_end = -1 })
		else
			local sep = string.rep("─", preview_w - 4)

			-- Title
			table.insert(lines, "")
			table.insert(lines, string.format("  %s %s", theme.icon("music"), utils.safe_truncate(item.title or "Unknown", preview_w - 6)))
			table.insert(hls, { line = #lines - 1, hl = "YtPlayerTitleText", col_start = 0, col_end = -1 })

			-- Channel
			local channel_name = (item.channel and item.channel ~= "") and item.channel or "Unknown Artist"
			table.insert(lines, string.format("    %s %s  %s", theme.icon("artist"), channel_name, theme.icon("verified")))
			table.insert(hls, { line = #lines - 1, hl = "YtPlayerArtist", col_start = 0, col_end = -1 })

			table.insert(lines, "  " .. sep)
			table.insert(hls, { line = #lines - 1, hl = "YtPlayerSeparator", col_start = 0, col_end = -1 })

			-- Duration
			local dur_str = (item.duration and item.duration > 0) and utils.format_time(item.duration) or "Live / Unknown"
			table.insert(lines, string.format("  %s Duration: %s", theme.icon("time"), dur_str))
			table.insert(hls, { line = #lines - 1, hl = "YtPlayerText", col_start = 0, col_end = -1 })

			-- Upload Date
			if item.upload_date and type(item.upload_date) == "string" and #item.upload_date == 8 then
				local y = item.upload_date:sub(1, 4)
				local m = item.upload_date:sub(5, 6)
				local d = item.upload_date:sub(7, 8)
				local date_str = string.format("%s-%s-%s", y, m, d)
				table.insert(lines, string.format("  %s Uploaded: %s", theme.icon("calendar"), date_str))
				table.insert(hls, { line = #lines - 1, hl = "YtPlayerText", col_start = 0, col_end = -1 })
			end

			-- Status
			local current_state = state_mod.get_current()
			local cur_pos = current_state.playlist_pos
			local active_url = (current_state.playlist and cur_pos and current_state.playlist[cur_pos + 1])
				and current_state.playlist[cur_pos + 1].filename or state.current_playing_url
			local is_playing = (active_url and item.url == active_url)

			if is_playing then
				table.insert(lines, string.format("  %s Status: Currently Playing", theme.icon("playing")))
				table.insert(hls, { line = #lines - 1, hl = "YtPlayerPlaying", col_start = 0, col_end = -1 })
			else
				table.insert(lines, string.format("  %s Status: Ready to Play", theme.icon("disc")))
				table.insert(hls, { line = #lines - 1, hl = "YtPlayerMuted", col_start = 0, col_end = -1 })
			end

			-- URL
			table.insert(lines, string.format("  %s URL: %s", theme.icon("search"), utils.safe_truncate(item.url, preview_w - 12)))
			table.insert(hls, { line = #lines - 1, hl = "YtPlayerMuted", col_start = 0, col_end = -1 })

			table.insert(lines, "")
			table.insert(lines, "  " .. sep)
			table.insert(hls, { line = #lines - 1, hl = "YtPlayerSeparator", col_start = 0, col_end = -1 })

			-- Actions
			table.insert(lines, "  Available Actions:")
			table.insert(hls, { line = #lines - 1, hl = "YtPlayerAccent", col_start = 0, col_end = -1 })
			table.insert(lines, "    [↵] Play Track Immediately")
			table.insert(lines, "    [a] Append Track to Queue")
			table.insert(lines, "    [s] Save Track to Local Playlist")
			table.insert(lines, "    [i] Focus Search Bar (New Query)")
			table.insert(lines, "    [L] Load More Results")
			for k = #lines - 4, #lines do
				table.insert(hls, { line = k - 1, hl = "YtPlayerKeyHint", col_start = 4, col_end = 7 })
			end
		end

		window.render(preview_buf, lines, hls)
	end

	-- Render Search Results List
	local function render_results()
		if not vim.api.nvim_buf_is_valid(results_buf) then
			return
		end

		local lines = {}
		local hls = {}

		local current_state = state_mod.get_current()
		local cur_pos = current_state.playlist_pos
		local cur_filename = (current_state.playlist and cur_pos and current_state.playlist[cur_pos + 1])
			and current_state.playlist[cur_pos + 1].filename or state.current_playing_url

		if #state.results == 0 then
			table.insert(lines, "")
			table.insert(lines, "   No results found.")
			table.insert(lines, "   Type a query in the search bar above and press Enter.")
			table.insert(hls, { line = 1, hl = "YtPlayerMuted", col_start = 0, col_end = -1 })
			table.insert(hls, { line = 2, hl = "YtPlayerKeyHint", col_start = 0, col_end = -1 })
		else
			for i, r in ipairs(state.results) do
				local is_playing = (cur_filename and r.url == cur_filename)
				local is_selected = (i == state.selected_idx)

				local prefix = is_playing and (theme.icon("playing") .. " ")
					or (is_selected and (theme.icon("selected") .. " ") or "   ")
				local num_str = string.format("%2d. ", i)
				local dur_str = (r.duration and r.duration > 0) and utils.format_time(r.duration) or ""
				local clean_title = utils.safe_truncate(r.title or "Unknown", results_w - 18)

				-- Line 1: Title
				local row_title = string.format("%s%s%s", prefix, num_str, clean_title)
				table.insert(lines, row_title)
				local title_line_idx = #lines - 1

				if is_playing then
					table.insert(hls, { line = title_line_idx, hl = "YtPlayerPlaying", col_start = 0, col_end = -1 })
				elseif is_selected then
					table.insert(hls, { line = title_line_idx, hl = "YtPlayerTitleText", col_start = 0, col_end = -1 })
				else
					table.insert(hls, { line = title_line_idx, hl = "YtPlayerText", col_start = 0, col_end = -1 })
					table.insert(hls, { line = title_line_idx, hl = "YtPlayerIndex", col_start = 3, col_end = 8 })
				end

				if dur_str ~= "" then
					table.insert(hls, {
						line = title_line_idx,
						virt_text = { { dur_str .. "  ", is_playing and "YtPlayerPlaying" or "YtPlayerDuration" } },
						virt_text_pos = "right_align",
					})
				end

				-- Line 2: Channel & Upload Date & Now Playing badge
				local channel = (r.channel and r.channel ~= "") and r.channel or "Unknown Channel"
				local date_str = ""
				if r.upload_date and type(r.upload_date) == "string" and #r.upload_date == 8 then
					date_str = string.format("%s-%s-%s", r.upload_date:sub(1, 4), r.upload_date:sub(5, 6), r.upload_date:sub(7, 8))
				end

				local meta_parts = { string.format("%s %s", theme.icon("artist"), channel) }
				if date_str ~= "" then
					table.insert(meta_parts, string.format("%s %s", theme.icon("calendar"), date_str))
				end
				if is_playing then
					table.insert(meta_parts, string.format("%s Now Playing", theme.icon("playing")))
				end

				local meta_line = "      " .. table.concat(meta_parts, "   ")
				table.insert(lines, meta_line)
				local meta_line_idx = #lines - 1
				table.insert(hls, { line = meta_line_idx, hl = is_playing and "YtPlayerPlaying" or "YtPlayerMuted", col_start = 0, col_end = -1 })

				-- Line 3: Separator
				local sep_line = "      " .. string.rep("─", results_w - 10)
				table.insert(lines, sep_line)
				table.insert(hls, { line = #lines - 1, hl = "YtPlayerSeparator", col_start = 0, col_end = -1 })
			end
		end

		window.render(results_buf, lines, hls)

		if #state.results > 0 and vim.api.nvim_win_is_valid(results_win) then
			pcall(vim.api.nvim_win_set_config, results_win, {
				title = string.format(" %s Results (%d) ", theme.icon("search"), #state.results),
				title_pos = "center",
			})
			local target_line = (math.max(1, state.selected_idx or 1) - 1) * LINES_PER_RESULT + 1
			pcall(vim.api.nvim_win_set_cursor, results_win, { target_line, 0 })
		end

		render_preview()
	end

	-- Jump selection safely and update cursor and preview
	local function jump_to(idx)
		if #state.results == 0 then return end
		state.selected_idx = math.max(1, math.min(#state.results, idx))
		local target_line = (state.selected_idx - 1) * LINES_PER_RESULT + 1
		if vim.api.nvim_win_is_valid(results_win) then
			pcall(vim.api.nvim_win_set_cursor, results_win, { target_line, 0 })
		end
		render_preview()
	end

	local function jump(delta)
		jump_to((state.selected_idx or 1) + delta)
	end

	-- Real-time cursor tracker (ensures preview ALWAYS refreshes on any cursor motion)
	local function on_cursor_moved()
		if not vim.api.nvim_win_is_valid(results_win) then return end
		if #state.results == 0 then return end
		local cur = vim.api.nvim_win_get_cursor(results_win)
		local line = cur[1]
		local item_idx = math.floor((line - 1) / LINES_PER_RESULT) + 1
		item_idx = math.max(1, math.min(#state.results, item_idx))
		if state.selected_idx ~= item_idx then
			state.selected_idx = item_idx
			render_preview()
		end
	end

	vim.api.nvim_create_autocmd({ "CursorMoved" }, {
		buffer = results_buf,
		callback = on_cursor_moved,
	})

	-- Search execution
	local function do_search()
		local lines = vim.api.nvim_buf_get_lines(prompt_buf, 0, 1, false)
		local q = vim.trim(lines[1] or "")
		if q == "" then
			return
		end

		state.query = q
		state.is_searching = true
		state.results = {}
		state.selected_idx = 1
		state.offset = 0
		state.has_more = true

		if state.job and not state.job:is_closing() then
			pcall(function() state.job:kill(15) end)
		end

		start_spinner("Searching YouTube for '" .. state.query .. "'...")

		local config_limit = (require("yt-player").config.search and require("yt-player").config.search.limit) or 15
		state.job = M.search(state.query, config_limit, 0, function(res, err)
			stop_spinner()
			state.is_searching = false
			state.job = nil

			if not vim.api.nvim_buf_is_valid(results_buf) then
				return
			end

			if err then
				vim.notify("YT Control: Search error: " .. err, vim.log.levels.ERROR)
				state.results = {}
				if vim.api.nvim_win_is_valid(results_win) then
					pcall(vim.api.nvim_win_set_config, results_win, { title = " ❌ Search Error ", title_pos = "center" })
				end
			else
				state.results = res
				state.offset = #res
			end

			render_results()

			if #state.results > 0 and vim.api.nvim_win_is_valid(results_win) then
				vim.api.nvim_set_current_win(results_win)
				jump_to(1)
			end
		end)
	end

	-- Pagination (load more results)
	local function load_more()
		if not state.has_more or state.is_searching or state.is_loading_more or #state.results == 0 then
			return
		end
		state.is_loading_more = true
		vim.notify("YT Control: Loading more results...", vim.log.levels.INFO)

		local config_limit = (require("yt-player").config.search and require("yt-player").config.search.limit) or 10
		M.search(state.query, config_limit, state.offset, function(new_res, err)
			state.is_loading_more = false
			if not vim.api.nvim_buf_is_valid(results_buf) then
				return
			end
			if err or #new_res == 0 then
				state.has_more = false
				vim.notify("YT Control: No more results available", vim.log.levels.INFO)
				return
			end
			for _, item in ipairs(new_res) do
				table.insert(state.results, item)
			end
			state.offset = state.offset + #new_res
			render_results()
		end)
	end

	-- Action: Play selected result
	local function play_result()
		local item = state.results[state.selected_idx]
		if item and item.url ~= "" then
			state.current_playing_url = item.url
			require("yt-player").load(item.url)
			vim.notify("YT Control: Playing -> " .. item.title, vim.log.levels.INFO)
			render_results()
		end
	end

	-- Action: Queue selected result
	local function append_result()
		local item = state.results[state.selected_idx]
		if item and item.url ~= "" then
			require("yt-player").queue(item)
			vim.notify("YT Control: Queued -> " .. item.title, vim.log.levels.INFO)
		end
	end

	-- Action: Save to playlist
	local function save_result()
		local item = state.results[state.selected_idx]
		if item and item.url ~= "" then
			require("yt-player.playlists").prompt_save(item)
		end
	end

	-- Prompt Buffer Keymaps
	vim.api.nvim_buf_set_lines(prompt_buf, 0, -1, false, { state.query })
	local po = { buffer = prompt_buf, silent = true, noremap = true }

	vim.keymap.set({ "n", "i" }, "<CR>", function()
		vim.cmd("stopinsert")
		do_search()
	end, po)

	vim.keymap.set({ "n", "i" }, "<Down>", function()
		vim.cmd("stopinsert")
		if #state.results > 0 and vim.api.nvim_win_is_valid(results_win) then
			vim.api.nvim_set_current_win(results_win)
			jump_to(state.selected_idx or 1)
		end
	end, po)

	vim.keymap.set({ "n", "i" }, "<C-j>", function()
		vim.cmd("stopinsert")
		if #state.results > 0 and vim.api.nvim_win_is_valid(results_win) then
			vim.api.nvim_set_current_win(results_win)
			jump_to(state.selected_idx or 1)
		end
	end, po)

	vim.keymap.set({ "n", "i" }, "<Tab>", function()
		vim.cmd("stopinsert")
		if #state.results > 0 and vim.api.nvim_win_is_valid(results_win) then
			vim.api.nvim_set_current_win(results_win)
			jump_to(state.selected_idx or 1)
		end
	end, po)

	vim.keymap.set({ "n", "i" }, "<Esc>", close_all, po)

	-- Results Buffer Keymaps
	local ro = { buffer = results_buf, silent = true, noremap = true }
	vim.keymap.set("n", "q", close_all, ro)
	vim.keymap.set("n", "<Esc>", close_all, ro)

	-- Navigation down
	vim.keymap.set("n", "j", function() jump(1) end, ro)
	vim.keymap.set("n", "<Down>", function() jump(1) end, ro)
	vim.keymap.set("n", "<C-j>", function() jump(1) end, ro)
	vim.keymap.set("n", "<Tab>", function() jump(1) end, ro)

	-- Navigation up
	vim.keymap.set("n", "k", function()
		if state.selected_idx <= 1 then
			vim.api.nvim_set_current_win(prompt_win)
			vim.cmd("startinsert!")
			return
		end
		jump(-1)
	end, ro)
	vim.keymap.set("n", "<Up>", function()
		if state.selected_idx <= 1 then
			vim.api.nvim_set_current_win(prompt_win)
			vim.cmd("startinsert!")
			return
		end
		jump(-1)
	end, ro)
	vim.keymap.set("n", "<C-k>", function()
		if state.selected_idx <= 1 then
			vim.api.nvim_set_current_win(prompt_win)
			vim.cmd("startinsert!")
			return
		end
		jump(-1)
	end, ro)
	vim.keymap.set("n", "<S-Tab>", function()
		if state.selected_idx <= 1 then
			vim.api.nvim_set_current_win(prompt_win)
			vim.cmd("startinsert!")
			return
		end
		jump(-1)
	end, ro)

	-- First and Last
	vim.keymap.set("n", "gg", function() jump_to(1) end, ro)
	vim.keymap.set("n", "G", function() jump_to(#state.results) end, ro)

	-- Play, Queue, Save
	vim.keymap.set("n", "<CR>", play_result, ro)
	vim.keymap.set("n", "a", append_result, ro)
	vim.keymap.set("n", "A", append_result, ro)
	vim.keymap.set("n", "<C-a>", append_result, ro)
	vim.keymap.set("n", "s", save_result, ro)

	-- Load more results
	vim.keymap.set("n", "L", load_more, ro)

	-- Return to search bar
	vim.keymap.set("n", "i", function()
		vim.api.nvim_set_current_win(prompt_win)
		vim.cmd("startinsert!")
	end, ro)
	vim.keymap.set("n", "/", function()
		vim.api.nvim_set_current_win(prompt_win)
		vim.cmd("startinsert!")
	end, ro)

	-- Preview Buffer Keymaps
	local pro = { buffer = preview_buf, silent = true, noremap = true }
	vim.keymap.set("n", "q", close_all, pro)
	vim.keymap.set("n", "<Esc>", close_all, pro)
	vim.keymap.set("n", "<CR>", play_result, pro)
	vim.keymap.set("n", "a", append_result, pro)
	vim.keymap.set("n", "s", save_result, pro)
	vim.keymap.set("n", "<Tab>", function()
		if vim.api.nvim_win_is_valid(results_win) then
			vim.api.nvim_set_current_win(results_win)
		end
	end, pro)

	render_results()

	if state.query ~= "" then
		do_search()
	else
		vim.cmd("startinsert!")
	end

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = prompt_buf,
		once = true,
		callback = close_all,
	})
end

M.open_picker = M.interactive_picker

return M
