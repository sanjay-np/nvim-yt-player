---@mod yt-player.playlists Persistent local playlists and modern manager
local M = {}

local utils = require("yt-player.utils")
local theme = require("yt-player.ui.theme")
local window = require("yt-player.ui.window")
local state_mod = require("yt-player.state")

local function get_path()
	return vim.fn.stdpath("data") .. "/yt-player-playlists.json"
end

--- Read all playlists
---@return table { [playlist_name] = { {title, url, duration, added_at}, ... } }
function M.get_all()
	local data, is_corrupt = utils.read_json_file(get_path(), {})
	if is_corrupt then
		vim.notify("YT Control: Warning - playlists file corrupted, preserving existing data", vim.log.levels.WARN)
	end
	return data
end

--- Write playlists to disk
local function save(data)
	utils.atomic_write_json(get_path(), data)
end

--- Save a track to a playlist
---@param playlist_name string
---@param track table
function M.add_track(playlist_name, track)
	if not track or not track.url or track.url == "" then
		return
	end
	if not playlist_name or playlist_name == "" then
		return
	end

	local lists = M.get_all()
	if type(lists[playlist_name]) ~= "table" then
		lists[playlist_name] = {}
	end

	-- Check for duplicate URL
	for _, item in ipairs(lists[playlist_name]) do
		if item.url == track.url then
			vim.notify("YT Control: Track already in playlist", vim.log.levels.WARN)
			return
		end
	end

	table.insert(lists[playlist_name], {
		title = track.title or "Unknown",
		url = track.url,
		duration = track.duration or 0,
		channel = track.channel or "",
		added_at = os.time(),
	})

	save(lists)
	vim.notify("YT Control: Added to '" .. playlist_name .. "'", vim.log.levels.INFO)
end

--- Remove a track or an entire playlist
function M.remove_something(playlist_name, track_url)
	local lists = M.get_all()
	if not lists[playlist_name] then
		return false
	end

	if track_url then
		local found = false
		local filtered = {}
		for _, item in ipairs(lists[playlist_name]) do
			if item.url == track_url then
				found = true
			else
				table.insert(filtered, item)
			end
		end
		lists[playlist_name] = filtered
		if found then
			save(lists)
			return true
		end
	else
		-- Remove the whole playlist
		lists[playlist_name] = nil
		save(lists)
		return true
	end
	return false
end

--- Helper to prompt selecting/creating a playlist to save a track
function M.prompt_save(track)
	if not track or not track.url or track.url == "" then
		vim.notify("YT Control: Invalid track to save", vim.log.levels.ERROR)
		return
	end

	local lists = M.get_all()
	local list_names = vim.tbl_keys(lists)
	table.sort(list_names)
	table.insert(list_names, 1, "[Create New Playlist]")

	vim.ui.select(list_names, {
		prompt = "Save to Playlist:",
	}, function(choice)
		if not choice then
			return
		end

		if choice == "[Create New Playlist]" then
			vim.schedule(function()
				vim.ui.input({ prompt = "New Playlist Name: " }, function(input)
					if input and vim.trim(input) ~= "" then
						M.add_track(vim.trim(input), track)
					end
				end)
			end)
		else
			M.add_track(choice, track)
		end
	end)
end

--- Play all tracks from a playlist
---@param playlist_name string
function M.play_all(playlist_name)
	local lists = M.get_all()
	local tracks = lists[playlist_name] or {}
	if #tracks == 0 then
		vim.notify("YT Control: Playlist is empty", vim.log.levels.WARN)
		return
	end

	local yt = require("yt-player")
	local mpv = require("yt-player.mpv")
	local state = state_mod

	state.current.playlist_meta = state.current.playlist_meta or {}
	state.current.artist_map = state.current.artist_map or {}

	for _, t in ipairs(tracks) do
		state.current.playlist_meta[t.url] = t.title or "Unknown"
		if t.channel and t.channel ~= "" then
			state.current.artist_map[t.url] = t.channel
		end
	end

	-- Start with first track
	yt.load(tracks[1].url)

	-- Append remaining tracks
	for i = 2, #tracks do
		mpv.send_command({ "loadfile", tracks[i].url, "append-play" })
	end

	vim.notify(string.format("YT Control: Playing playlist '%s' (%d tracks)", playlist_name, #tracks), vim.log.levels.INFO)
end

--- Append all tracks from a playlist to queue
---@param playlist_name string
function M.queue_all(playlist_name)
	local lists = M.get_all()
	local tracks = lists[playlist_name] or {}
	if #tracks == 0 then
		vim.notify("YT Control: Playlist is empty", vim.log.levels.WARN)
		return
	end

	local yt = require("yt-player")
	for _, t in ipairs(tracks) do
		yt.queue(t, true)
	end
	vim.notify(string.format("YT Control: Queued %d tracks from '%s'", #tracks, playlist_name), vim.log.levels.INFO)
end

--- Open Modern Master-Detail Playlist Manager
function M.open_manager()
	local lists = M.get_all()
	local list_names = vim.tbl_keys(lists)
	table.sort(list_names)

	local total_w = math.floor(vim.o.columns * 0.8)
	local left_w = math.max(26, math.floor(total_w * 0.32))
	local right_w = total_w - left_w - 2
	local height = math.floor(vim.o.lines * 0.72)
	local row = math.max(0, math.floor((vim.o.lines - height) / 2))
	local col = math.max(0, math.floor((vim.o.columns - total_w) / 2))

	local left_buf = vim.api.nvim_create_buf(false, true)
	local right_buf = vim.api.nvim_create_buf(false, true)

	local winhl = "Normal:YtPlayerNormal,NormalNC:YtPlayerNormal,NormalFloat:YtPlayerNormal,FloatBorder:YtPlayerBorder,FloatTitle:YtPlayerTitle,FloatFooter:YtPlayerFooter,CursorLine:YtPlayerSelected"

	local left_win = vim.api.nvim_open_win(left_buf, true, {
		relative = "editor",
		row = row,
		col = col,
		width = left_w,
		height = height,
		style = "minimal",
		border = "rounded",
		title = string.format(" %s Playlists ", theme.icon("playlist")),
		title_pos = "center",
		footer = " [n] New  [r] Rename  [dd] Del ",
		footer_pos = "center",
	})

	local right_win = vim.api.nvim_open_win(right_buf, false, {
		relative = "editor",
		row = row,
		col = col + left_w + 2,
		width = right_w,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " Tracks ",
		title_pos = "center",
		footer = " [↵] Play  [a] Queue  [P] Play All  [dd] Remove ",
		footer_pos = "center",
	})

	for _, w in ipairs({ left_win, right_win }) do
		vim.wo[w].winhighlight = winhl
		vim.wo[w].cursorline = true
		vim.wo[w].number = false
		vim.wo[w].relativenumber = false
		vim.wo[w].signcolumn = "no"
	end

	vim.bo[left_buf].buftype = "nofile"
	vim.bo[left_buf].bufhidden = "wipe"
	vim.bo[right_buf].buftype = "nofile"
	vim.bo[right_buf].bufhidden = "wipe"

	local selected_playlist_idx = 1
	local active_pane = "left" -- "left" | "right"

	local function get_active_playlist_name()
		if #list_names == 0 then
			return nil
		end
		return list_names[selected_playlist_idx]
	end

	local function get_active_tracks()
		local name = get_active_playlist_name()
		if not name then
			return {}
		end
		return lists[name] or {}
	end

	local function render_left()
		if not vim.api.nvim_buf_is_valid(left_buf) then
			return
		end
		local lines = {}
		local hls = {}

		if #list_names == 0 then
			table.insert(lines, "")
			table.insert(lines, "   (No playlists found)")
			table.insert(lines, "   Press 'n' to create one")
			table.insert(hls, { line = 1, hl = "YtPlayerMuted", col_start = 0, col_end = -1 })
			table.insert(hls, { line = 2, hl = "YtPlayerKeyHint", col_start = 0, col_end = -1 })
		else
			for i, name in ipairs(list_names) do
				local count = #(lists[name] or {})
				local is_active = (i == selected_playlist_idx)
				local prefix = is_active and (theme.icon("selected") .. " ") or "  "
				local folder = theme.icon("folder") .. " "
				local clean_name = utils.safe_truncate(name, left_w - 12)
				local row = string.format(" %s%s%s", prefix, folder, clean_name)
				table.insert(lines, row)

				local hl = is_active and "YtPlayerTitleText" or "YtPlayerText"
				table.insert(hls, { line = #lines - 1, hl = hl, col_start = 0, col_end = -1 })
				table.insert(hls, {
					line = #lines - 1,
					virt_text = { { string.format("[%d]  ", count), "YtPlayerMuted" } },
					virt_text_pos = "right_align",
				})
			end
		end

		window.render(left_buf, lines, hls)
		if #list_names > 0 and vim.api.nvim_win_is_valid(left_win) then
			pcall(vim.api.nvim_win_set_cursor, left_win, { math.max(1, selected_playlist_idx), 0 })
		end
	end

	local function render_right()
		if not vim.api.nvim_buf_is_valid(right_buf) then
			return
		end
		local tracks = get_active_tracks()
		local lines = {}
		local hls = {}

		local current_state = state_mod.get_current()
		local cur_pos = current_state.playlist_pos
		local cur_filename = (current_state.playlist and cur_pos and current_state.playlist[cur_pos + 1])
			and current_state.playlist[cur_pos + 1].filename or nil

		local pl_name = get_active_playlist_name()
		if pl_name and vim.api.nvim_win_is_valid(right_win) then
			pcall(vim.api.nvim_win_set_config, right_win, {
				title = string.format(" %s %s (%d tracks) ", theme.icon("playlist"), pl_name, #tracks),
				title_pos = "center",
			})
		end

		if #tracks == 0 then
			table.insert(lines, "")
			table.insert(lines, "   (Playlist is empty)")
			table.insert(lines, "   Add tracks with 's' during search or playback")
			table.insert(hls, { line = 1, hl = "YtPlayerMuted", col_start = 0, col_end = -1 })
			table.insert(hls, { line = 2, hl = "YtPlayerKeyHint", col_start = 0, col_end = -1 })
		else
			for i, t in ipairs(tracks) do
				local is_playing = cur_filename and (t.url == cur_filename)
				local prefix = is_playing and (theme.icon("playing") .. " ") or string.format("%2d. ", i)
				local dur_str = (t.duration and t.duration > 0) and utils.format_time(t.duration) or ""
				local clean_title = utils.safe_truncate(t.title or "Unknown", right_w - 20)

				table.insert(lines, string.format("  %s%s", prefix, clean_title))
				local line_idx = #lines - 1

				if is_playing then
					table.insert(hls, { line = line_idx, hl = "YtPlayerPlaying", col_start = 0, col_end = -1 })
				else
					table.insert(hls, { line = line_idx, hl = "YtPlayerText", col_start = 0, col_end = -1 })
					table.insert(hls, { line = line_idx, hl = "YtPlayerIndex", col_start = 2, col_end = 6 })
				end

				if dur_str ~= "" then
					table.insert(hls, {
						line = line_idx,
						virt_text = { { dur_str .. "   ", is_playing and "YtPlayerPlaying" or "YtPlayerDuration" } },
						virt_text_pos = "right_align",
					})
				end
			end
		end

		window.render(right_buf, lines, hls)
	end

	local function refresh_all()
		lists = M.get_all()
		list_names = vim.tbl_keys(lists)
		table.sort(list_names)
		selected_playlist_idx = math.max(1, math.min(#list_names, selected_playlist_idx))
		render_left()
		render_right()
	end

	local function close_all()
		window.safe_close(left_win, left_buf)
		window.safe_close(right_win, right_buf)
	end

	-- Left Keymaps
	local lo = { buffer = left_buf, silent = true, noremap = true }
	vim.keymap.set("n", "q", close_all, lo)
	vim.keymap.set("n", "<Esc>", close_all, lo)

	vim.keymap.set("n", "j", function()
		if #list_names == 0 then
			return
		end
		selected_playlist_idx = math.min(#list_names, selected_playlist_idx + 1)
		render_left()
		render_right()
	end, lo)

	vim.keymap.set("n", "k", function()
		if #list_names == 0 then
			return
		end
		selected_playlist_idx = math.max(1, selected_playlist_idx - 1)
		render_left()
		render_right()
	end, lo)

	vim.keymap.set("n", "<Tab>", function()
		if #get_active_tracks() > 0 and vim.api.nvim_win_is_valid(right_win) then
			active_pane = "right"
			vim.api.nvim_set_current_win(right_win)
			pcall(vim.api.nvim_win_set_cursor, right_win, { 1, 0 })
		end
	end, lo)

	vim.keymap.set("n", "l", function()
		if #get_active_tracks() > 0 and vim.api.nvim_win_is_valid(right_win) then
			active_pane = "right"
			vim.api.nvim_set_current_win(right_win)
			pcall(vim.api.nvim_win_set_cursor, right_win, { 1, 0 })
		end
	end, lo)

	vim.keymap.set("n", "<CR>", function()
		if #get_active_tracks() > 0 and vim.api.nvim_win_is_valid(right_win) then
			active_pane = "right"
			vim.api.nvim_set_current_win(right_win)
			pcall(vim.api.nvim_win_set_cursor, right_win, { 1, 0 })
		end
	end, lo)

	-- Create new playlist
	vim.keymap.set("n", "n", function()
		vim.ui.input({ prompt = "New Playlist Name: " }, function(input)
			if input and vim.trim(input) ~= "" then
				local name = vim.trim(input)
				local all = M.get_all()
				if not all[name] then
					all[name] = {}
					save(all)
					vim.notify("YT Control: Created playlist '" .. name .. "'", vim.log.levels.INFO)
					refresh_all()
				else
					vim.notify("YT Control: Playlist already exists", vim.log.levels.WARN)
				end
			end
		end)
	end, lo)

	-- Rename playlist
	vim.keymap.set("n", "r", function()
		local old_name = get_active_playlist_name()
		if not old_name then
			return
		end
		vim.ui.input({ prompt = "Rename '" .. old_name .. "' to: ", default = old_name }, function(input)
			if input and vim.trim(input) ~= "" and vim.trim(input) ~= old_name then
				local new_name = vim.trim(input)
				local all = M.get_all()
				all[new_name] = all[old_name]
				all[old_name] = nil
				save(all)
				vim.notify(string.format("YT Control: Renamed to '%s'", new_name), vim.log.levels.INFO)
				refresh_all()
			end
		end)
	end, lo)

	-- Delete playlist
	vim.keymap.set("n", "dd", function()
		local name = get_active_playlist_name()
		if not name then
			return
		end
		vim.ui.select({ "No, Cancel", "Yes, Delete Playlist" }, {
			prompt = string.format("Delete playlist '%s'?", name),
		}, function(choice)
			if choice == "Yes, Delete Playlist" then
				M.remove_something(name)
				vim.notify("YT Control: Deleted playlist '" .. name .. "'", vim.log.levels.INFO)
				selected_playlist_idx = math.max(1, selected_playlist_idx - 1)
				refresh_all()
			end
		end)
	end, lo)

	-- Play all / Queue all from left pane
	vim.keymap.set("n", "P", function()
		local name = get_active_playlist_name()
		if name then
			M.play_all(name)
		end
	end, lo)

	vim.keymap.set("n", "A", function()
		local name = get_active_playlist_name()
		if name then
			M.queue_all(name)
		end
	end, lo)

	-- Right Keymaps (Tracks)
	local ro = { buffer = right_buf, silent = true, noremap = true }
	vim.keymap.set("n", "q", close_all, ro)
	vim.keymap.set("n", "<Esc>", close_all, ro)

	vim.keymap.set("n", "<Tab>", function()
		active_pane = "left"
		if vim.api.nvim_win_is_valid(left_win) then
			vim.api.nvim_set_current_win(left_win)
		end
	end, ro)

	vim.keymap.set("n", "h", function()
		active_pane = "left"
		if vim.api.nvim_win_is_valid(left_win) then
			vim.api.nvim_set_current_win(left_win)
		end
	end, ro)

	-- Play track
	vim.keymap.set("n", "<CR>", function()
		local tracks = get_active_tracks()
		local r = vim.api.nvim_win_get_cursor(right_win)[1]
		local t = tracks[r]
		if t then
			require("yt-player").load(t.url)
			vim.defer_fn(render_right, 200)
		end
	end, ro)

	-- Queue track
	vim.keymap.set("n", "a", function()
		local tracks = get_active_tracks()
		local r = vim.api.nvim_win_get_cursor(right_win)[1]
		local t = tracks[r]
		if t then
			require("yt-player").queue(t)
		end
	end, ro)

	-- Remove track from playlist
	vim.keymap.set("n", "dd", function()
		local tracks = get_active_tracks()
		local pl_name = get_active_playlist_name()
		local r = vim.api.nvim_win_get_cursor(right_win)[1]
		local t = tracks[r]
		if t and pl_name then
			M.remove_something(pl_name, t.url)
			refresh_all()
			local new_tracks = get_active_tracks()
			if vim.api.nvim_win_is_valid(right_win) and #new_tracks > 0 then
				pcall(vim.api.nvim_win_set_cursor, right_win, { math.min(r, #new_tracks), 0 })
			end
		end
	end, ro)

	-- Play all
	vim.keymap.set("n", "P", function()
		local name = get_active_playlist_name()
		if name then
			M.play_all(name)
		end
	end, ro)

	render_left()
	render_right()

	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = left_buf,
		once = true,
		callback = close_all,
	})
end

return M
