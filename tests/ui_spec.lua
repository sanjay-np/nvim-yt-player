-- Run from the project root:
-- nvim --headless -u NONE -i NONE -n -c 'set rtp+=.' -c 'lua dofile("tests/ui_spec.lua")'
-- Fixture data and IPC stubs keep these checks offline and out of user libraries.
local function run()
	local api = vim.api
	local theme = require("yt-player.ui.theme")
	local state = require("yt-player.state").current
	local hub = require("yt-player.ui.hub")
	local player = require("yt-player.player")
	local search = require("yt-player.search")
	local playlists = require("yt-player.playlists")
	local history = require("yt-player.history")
	local yt = require("yt-player")
	local commands, requests, loaded, queued, saved = {}, {}, {}, {}, {}
	local tracks, library = {}, {}
	for index = 1, 100 do
		tracks[index] = {
			title = string.format("夜に聴く音楽 · Track %03d — café / long title with extra detail", index),
			channel = "A very long channel name · 音楽 " .. index,
			url = "https://www.youtube.com/watch?v=fixture" .. index,
			filename = "https://www.youtube.com/watch?v=fixture" .. index,
			duration = index * 12, timestamp = os.time() - index * 3600,
		}
		library[string.format("Playlist %03d · お気に入り", index)] = vim.deepcopy(tracks)
	end
	playlists.get_all = function() return library end
	history.get = function() return tracks end
	history.add = function() end
	playlists.prompt_save = function(item) table.insert(saved, item) end
	yt.command = function(command) table.insert(commands, command) end
	require("yt-player.mpv").send_command = yt.command
	yt.load = function(url) table.insert(loaded, url) end
	yt.queue = function(item) table.insert(queued, item) end
	search.search = function(query, count, offset, callback)
		table.insert(requests, { query = query, count = count, offset = offset, callback = callback })
	end
	vim.notify = function() end
	theme.setup({ nerd_fonts = false })
	state.title, state.artist = tracks[1].title, tracks[1].channel
	state.playing, state.duration, state.position = true, 300, 123
	state.playlist, state.playlist_pos = tracks, 0

	local checks = 0
	local function check(condition, message)
		checks = checks + 1
		assert(condition, message)
	end
	local function key(buffer, lhs)
		for _, map in ipairs(api.nvim_buf_get_keymap(buffer, "n")) do
			if map.lhs == lhs or map.lhs == lhs:gsub("<Space>", " ") then
				check(type(map.callback) == "function", "Missing callback: " .. lhs)
				map.callback()
				return
			end
		end
		error("Missing mapping: " .. lhs)
	end
	local function size(columns, lines)
		vim.o.columns, vim.o.lines = columns, lines
		api.nvim_exec_autocmds("VimResized", {})
	end
	local function fits(win, buf, bounded)
		local width, height = api.nvim_win_get_width(win), api.nvim_win_get_height(win)
		local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
		for row, line in ipairs(lines) do
			check(vim.fn.strdisplaywidth(line) <= width, string.format("Row %d overflows %d columns: %s", row, width, line))
		end
		if bounded then check(#lines <= height, string.format("View overflows: %d rows in %d", #lines, height)) end
		return lines
	end
	local function selection_visible(column, index)
		local row = hub.item_rows[column][index]
		check(row ~= nil, "Selected item is outside viewport: " .. index)
		check(api.nvim_win_get_cursor(hub.win_id)[1] == row, "Cursor and selection disagree")
		check(hub.row_indices[column][row] == index, "Row maps to the wrong action")
	end

	-- Every populated view adapts and keeps the last item actionable.
	for _, dimensions in ipairs({ { 160, 48 }, { 120, 36 }, { 100, 28 }, { 80, 24 }, { 80, 21 }, { 60, 20 }, { 40, 18 }, { 40, 14 } }) do
		size(dimensions[1], dimensions[2])
		hub.open(1)
		hub.search_results = tracks
		for tab = 1, 5 do
			hub.open(tab)
			vim.cmd("stopinsert")
			api.nvim_set_current_win(hub.win_id)
			key(hub.buf_id, "G")
			fits(hub.win_id, hub.buf_id, true)
			selection_visible(1, 100)
			if dimensions[1] >= 60 and dimensions[2] >= 21 then
				local last_line = api.nvim_buf_get_lines(hub.buf_id, -2, -1, false)[1] or ""
				check(last_line:find("[Space]", 1, true) ~= nil, "Transport disappeared on tab " .. tab)
			end
			if tab == 4 then
				key(hub.buf_id, "l")
				key(hub.buf_id, "G")
				fits(hub.win_id, hub.buf_id, true)
				selection_visible(2, 100)
				key(hub.buf_id, "h")
			end
		end
		hub.close()
		player.open_float()
		fits(player.float.win_id, player.float.buf_id, true)
		player.close_float()
	end

	-- Paused and disabled visualizers stay still, while playback remains visible.
	size(160, 48)
	hub.open(1)
	local visualizer = require("yt-player.ui.components.visualizer")
	for _ = 1, 4 do
		if visualizer.current_style == "none" then break end
		key(hub.buf_id, "v")
	end
	local stopped = api.nvim_buf_get_lines(hub.buf_id, 0, -1, false)
	check(table.concat(stopped):find("VISUALIZER OFF", 1, true) ~= nil, "Visualizer off state is missing")
	vim.wait(300, function() return false end)
	check(vim.deep_equal(stopped, api.nvim_buf_get_lines(hub.buf_id, 0, -1, false)), "Visualizer kept animating when disabled")
	key(hub.buf_id, "v")
	state.playing = false
	hub.refresh()
	local paused = api.nvim_buf_get_lines(hub.buf_id, 0, -1, false)
	check(table.concat(paused):find("PAUSED", 1, true) ~= nil, "Paused deck lost its status")
	vim.wait(300, function() return false end)
	check(vim.deep_equal(paused, api.nvim_buf_get_lines(hub.buf_id, 0, -1, false)), "Paused deck kept animating")
	state.playing = true
	hub.close()

	-- Playing an item, deleting it, and saving it use its data index after scrolling.
	size(120, 36)
	hub.open(1)
	hub.select(83)
	key(hub.buf_id, "<CR>")
	check(vim.deep_equal(commands[#commands], { "playlist-play-index", 82 }), "Deck played the wrong item")
	key(hub.buf_id, "dd")
	check(vim.deep_equal(commands[#commands], { "playlist-remove", 82 }), "Deck removed the wrong item")
	key(hub.buf_id, "s")
	check(saved[#saved].url == tracks[83].url, "Saved the wrong queue track")
	key(hub.buf_id, "p")
	check(vim.deep_equal(commands[#commands], { "cycle", "pause" }), "p must toggle playback")
	hub.open(3)
	hub.select(50)
	key(hub.buf_id, "J")
	check(vim.deep_equal(commands[#commands], { "playlist-move", 49, 51 }), "Move down has wrong mpv indices")
	check(hub.selection[3] == 51, "Moved track lost selection")
	key(hub.buf_id, "K")
	check(vim.deep_equal(commands[#commands], { "playlist-move", 50, 49 }), "Move up has wrong mpv indices")
	hub.refresh()
	local clicked_row = hub.item_rows[1][51]
	api.nvim_win_set_cursor(hub.win_id, { clicked_row, 0 })
	api.nvim_exec_autocmds("CursorMoved", { buffer = hub.buf_id })
	check(hub.selection[3] == 51, "Moving the cursor did not update the selected data item")
	hub.open(5)
	hub.select(100)
	key(hub.buf_id, "<CR>")
	check(loaded[#loaded] == tracks[100].url, "History cannot replay its final item")
	key(hub.buf_id, "a")
	check(queued[#queued].url == tracks[100].url, "History queued the wrong item")

	-- Resizing an open hub updates both layout and the embedded input.
	hub.open(2)
	size(60, 20)
	fits(hub.win_id, hub.buf_id, true)
	check(api.nvim_win_get_width(hub.search_prompt_win) <= api.nvim_win_get_width(hub.win_id) - 4, "Search prompt overflowed after resize")
	size(120, 36)
	fits(hub.win_id, hub.buf_id, true)

	-- Playlist management preserves existing names and follows the edited item.
	hub.open(4)
	hub.playlist_col = 1
	hub.select(1)
	local utils = require("yt-player.utils")
	local original_input, original_write = vim.ui.input, utils.atomic_write_json
	local writes = 0
	utils.atomic_write_json = function() writes = writes + 1; return true end
	local first_name, second_name = hub.playlist_names[1], hub.playlist_names[2]
	vim.ui.input = function(_, callback) callback(second_name) end
	key(hub.buf_id, "r")
	check(writes == 0 and library[first_name] ~= nil, "Rename overwrote an existing playlist")
	key(hub.buf_id, "N")
	check(writes == 0, "Creating an existing playlist should not write")
	vim.ui.input = function(_, callback) callback("A new playlist") end
	key(hub.buf_id, "N")
	check(writes == 1 and hub.playlist_names[hub.selected_pl_idx] == "A new playlist", "New playlist is not selected")
	vim.ui.input = function(_, callback) callback("Z renamed playlist") end
	key(hub.buf_id, "r")
	check(writes == 2 and hub.playlist_names[hub.selected_pl_idx] == "Z renamed playlist", "Renamed playlist lost selection")
	vim.ui.input, utils.atomic_write_json = original_input, original_write
	local original_select = vim.ui.select
	local removed = false
	playlists.remove_something = function() removed = true end
	vim.ui.select = function(_, _, callback) callback("Cancel") end
	key(hub.buf_id, "dd")
	check(not removed, "Cancel still deleted a playlist")
	vim.ui.select = function(_, _, callback) callback("Delete playlist") end
	key(hub.buf_id, "dd")
	check(removed, "Confirmed playlist deletion did not run")
	vim.ui.select = original_select

	-- A live timer refresh uses the same layout without stealing search focus.
	hub.open(2)
	local focused_prompt = hub.search_prompt_win
	check(api.nvim_win_get_config(focused_prompt).row == hub.header_height, "Search field overlaps the new application header")
	vim.wait(300, function() return false end)
	check(api.nvim_get_current_win() == focused_prompt, "Live refresh stole search input focus")

	-- Input drafts survive refreshes, tab switches, and closing the hub.
	hub.open(2)
	api.nvim_buf_set_lines(hub.search_prompt_buf, 0, -1, false, { "unfinished query" })
	hub.refresh()
	check(api.nvim_buf_get_lines(hub.search_prompt_buf, 0, 1, false)[1] == "unfinished query", "Refresh erased input")
	hub.switch_tab(3)
	hub.switch_tab(2)
	check(api.nvim_buf_get_lines(hub.search_prompt_buf, 0, 1, false)[1] == "unfinished query", "Tab switch erased input")
	local prompt_buf = hub.search_prompt_buf
	hub.close()
	check(not api.nvim_buf_is_valid(prompt_buf), "Search buffer leaked after close")
	hub.open(2)
	check(api.nvim_buf_get_lines(hub.search_prompt_buf, 0, 1, false)[1] == "unfinished query", "Reopening erased input")

	-- Out-of-order async responses and responses after close are ignored.
	yt.config.search.limit = 3
	hub.run_search("older query")
	local older = requests[#requests]
	hub.run_search("newer query")
	local newer = requests[#requests]
	check(newer.count == 3, "Search ignored configured limit")
	newer.callback({ tracks[3], tracks[4], tracks[5] })
	vim.wait(20, function() return not hub.search_loading end)
	older.callback({ tracks[1] })
	vim.wait(20, function() return false end)
	check(hub.search_results[1] == tracks[3], "Stale search replaced newer results")
	hub.load_more_search()
	local more = requests[#requests]
	check(more.offset == 3, "Pagination offset is incorrect")
	more.callback({ tracks[6] })
	vim.wait(20, function() return not hub.search_loading_more end)
	check(#hub.search_results == 4 and not hub.search_has_more, "Pagination did not reach end")
	hub.run_search("no matches")
	requests[#requests].callback({})
	vim.wait(20, function() return not hub.search_loading end)
	local content = table.concat(fits(hub.win_id, hub.buf_id, true), "\n")
	check(content:find("No results", 1, true) ~= nil, "Missing no-results feedback")
	hub.run_search("offline")
	requests[#requests].callback({}, "Network unavailable\nTry again")
	vim.wait(20, function() return not hub.search_loading end)
	content = table.concat(fits(hub.win_id, hub.buf_id, true), "\n")
	check(content:find("Network unavailable", 1, true) ~= nil, "Missing search-error feedback")
	hub.run_search("close before response")
	local pending = requests[#requests]
	hub.close()
	pending.callback({ tracks[8] })
	vim.wait(20, function() return false end)
	check(#hub.search_results == 0, "Closed hub accepted a pending response")
	check(hub.update_timer == nil, "Hub timer leaked")

	-- Empty views, help, and closing through Neovim's window commands are safe.
	state.title, state.playing, state.playlist = nil, false, {}
	tracks, library = {}, {}
	hub.reset_search()
	for tab = 1, 5 do
		hub.open(tab)
		fits(hub.win_id, hub.buf_id, true)
		key(hub.buf_id, "j")
		key(hub.buf_id, "<CR>")
		hub.close()
	end
	hub.open(2)
	hub.show_help()
	fits(hub.help.win, hub.help.buf, false)
	check(api.nvim_win_get_config(hub.help.win).zindex > api.nvim_win_get_config(hub.search_prompt_win).zindex, "Search covers help")
	hub.close()
	hub.open(1)
	api.nvim_win_close(hub.win_id, true)
	check(hub.win_id == nil and hub.update_timer == nil, "External window close leaked hub state")
	player.open_float()
	key(player.float.buf_id, "<Space>")
	check(vim.deep_equal(commands[#commands], { "cycle", "pause" }), "Mini Space mapping is incorrect")
	state.position = 239
	check(vim.wait(500, function()
		return table.concat(api.nvim_buf_get_lines(player.float.buf_id, 0, -1, false)):find("3:59", 1, true) ~= nil
	end), "Mini timer did not refresh playback position")
	fits(player.float.win_id, player.float.buf_id, true)
	api.nvim_win_close(player.float.win_id, true)
	check(player.float.win_id == nil and player.float.update_timer == nil, "Mini cleanup failed")
	player.open_panel()
	fits(player.panel.win_id, player.panel.buf_id, false)
	api.nvim_win_close(player.panel.win_id, true)
	check(player.panel.win_id == nil and player.panel.update_timer == nil, "Sidebar cleanup failed")
	size(20, 10)
	hub.open(2)
	fits(hub.win_id, hub.buf_id, true)
	check(hub.search_prompt_win == nil, "Tiny-terminal fallback should not create an input outside the hub")
	hub.close()

	-- Font auto mode is usable without a patched terminal font.
	vim.g.have_nerd_font = nil
	theme.setup({ nerd_fonts = "auto" })
	check(not theme.use_nerd_fonts, "Font auto mode should use portable icons by default")
	vim.g.have_nerd_font = true
	theme.setup({ nerd_fonts = "auto" })
	check(theme.use_nerd_fonts, "Font auto mode ignored have_nerd_font")
	size(120, 36)
	for tab = 1, 5 do
		hub.open(tab)
		fits(hub.win_id, hub.buf_id, true)
		hub.close()
	end

	-- Neovim 0.9 has no float footers; keep shortcuts visible in the body.
	local original_has = vim.fn.has
	vim.fn.has = function(feature) return feature == "nvim-0.10" and 0 or original_has(feature) end
	theme.setup({ nerd_fonts = false })
	size(80, 24)
	for tab = 1, 5 do
		hub.open(tab)
		local lines = fits(hub.win_id, hub.buf_id, true)
		check(lines[#lines]:find("? Help", 1, true) ~= nil, "Missing shortcuts without float-footer support")
		hub.close()
	end
	vim.fn.has = original_has
	print(string.format("UI regression checks passed (%d assertions)", checks))
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
	io.stderr:write(err .. "\n")
	vim.cmd("cquit 1")
else
	vim.cmd("qa!")
end
