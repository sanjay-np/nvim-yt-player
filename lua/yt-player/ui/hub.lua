---@mod yt-player.ui.hub Unified keyboard-driven music hub
local M = {}

local uv = vim.uv or vim.loop
local utils = require("yt-player.utils")
local state_mod = require("yt-player.state")
local theme = require("yt-player.ui.theme")
local window = require("yt-player.ui.window")
local views = require("yt-player.ui.views")
local visualizer = require("yt-player.ui.components.visualizer")

M.win_id = nil
M.buf_id = nil
M.update_timer = nil
M.active_tab = 1 -- 1: Deck, 2: Search, 3: Queue, 4: Playlists, 5: History

-- Embedded Search Prompt Window & Buffer (Tab 2)
M.search_prompt_win = nil
M.search_prompt_buf = nil
M.search_query = ""
M.search_results = {}
M.search_loading = false
M.search_loading_more = false
M.search_has_more = true
M.search_error = nil
M.search_selected_idx = 1
M.spinner_idx = 1
M.search_generation = 0
M.selection = { [1] = 1, [3] = 1, [5] = 1 }
M.item_rows = { {}, {} }
M.row_indices = { {}, {} }

-- Playlists state (Tab 4)
M.playlist_names = {}
M.selected_pl_idx = 1
M.selected_pl_track_idx = 1
M.playlist_col = 1 -- 1: left (playlists list), 2: right (tracks in playlist)

local TABS = {
	{ id = 1, name = "Deck", icon_key = "music" },
	{ id = 2, name = "Search", icon_key = "search" },
	{ id = 3, name = "Queue", icon_key = "queue" },
	{ id = 4, name = "Playlists", icon_key = "playlist" },
	{ id = 5, name = "History", icon_key = "history" },
}

--- Execute a YouTube search within the Hub
---@param query string
---@param append boolean|nil
function M.run_search(query, append)
	query = vim.trim(query or "")
	if query == "" then
		return
	end

	M.search_query = query
	if not append then M.search_draft = query end
	M.search_generation = M.search_generation + 1
	local generation = M.search_generation
	if not append and M.search_prompt_buf and vim.api.nvim_buf_is_valid(M.search_prompt_buf) then
		vim.api.nvim_buf_set_lines(M.search_prompt_buf, 0, -1, false, { query })
	end
	M.search_error = nil
	if not append then
		M.search_results = {}
		M.search_selected_idx = 1
		M.search_has_more = true
		M.search_loading = true
		M.search_loading_more = false
	else
		M.search_loading_more = true
	end
	M.refresh()

	local offset = append and #M.search_results or 0
	local limit = math.max(1, tonumber(require("yt-player").config.search.limit) or 10)
	local search_mod = require("yt-player.search")
	search_mod.search(query, limit, offset, function(results, err)
		vim.schedule(function()
			if generation ~= M.search_generation then return end
			results = results or {}
			M.search_loading = false
			M.search_loading_more = false

			if err and err ~= "" and #results == 0 then
				M.search_error = err
				if append then
					M.search_has_more = false
				end
			else
				if append then
					if #results == 0 then
						M.search_has_more = false
					else
						for _, item in ipairs(results) do
							table.insert(M.search_results, item)
						end
						if #results < limit then
							M.search_has_more = false
						end
					end
				else
					M.search_results = results
					M.search_has_more = (#results >= limit)
				end
			end
			M.refresh()
		end)
	end)
end

--- Load more search results (pagination) in the Hub search tab
function M.load_more_search()
	if M.active_tab ~= 2 then
		return
	end
	if M.search_loading or M.search_loading_more then
		return
	end
	if M.search_query == "" or #M.search_results == 0 then
		return
	end
	if not M.search_has_more then
		vim.notify("YT Player: No more results available", vim.log.levels.INFO)
		return
	end
	M.run_search(M.search_query, true)
end

--- Reset search state (used when opening a fresh search)
function M.reset_search()
	M.search_generation = M.search_generation + 1
	M.search_draft = ""
	M.search_query = ""
	M.search_results = {}
	M.search_error = nil
	M.search_selected_idx = 1
	M.search_has_more = true
	M.search_loading = false
	M.search_loading_more = false
end

--- Ensure the embedded search prompt window exists and is positioned correctly
---@param focus boolean|nil
function M.ensure_search_prompt(focus)
	if not M.win_id or not vim.api.nvim_win_is_valid(M.win_id) then
		return
	end

	local win_w = vim.api.nvim_win_get_width(M.win_id)
	if win_w < 24 or vim.api.nvim_win_get_height(M.win_id) < 8 then
		M.close_search_prompt()
		return
	end
	local p_w = math.max(1, win_w - 6)

	if M.search_prompt_win and vim.api.nvim_win_is_valid(M.search_prompt_win) then
		pcall(vim.api.nvim_win_set_config, M.search_prompt_win, {
			width = p_w,
			row = M.header_height or 2,
			col = 2,
			relative = "win",
			win = M.win_id,
			zindex = 60,
		})
		if focus then
			vim.api.nvim_set_current_win(M.search_prompt_win)
			vim.cmd("startinsert!")
		end
		return
	end

	if not M.search_prompt_buf or not vim.api.nvim_buf_is_valid(M.search_prompt_buf) then
		M.search_prompt_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[M.search_prompt_buf].buftype = "nofile"
		vim.bo[M.search_prompt_buf].bufhidden = "wipe"
		vim.bo[M.search_prompt_buf].swapfile = false
	end

	vim.bo[M.search_prompt_buf].modifiable = true
	vim.api.nvim_buf_set_lines(M.search_prompt_buf, 0, -1, false, { M.search_draft or M.search_query or "" })

	local config = {
		relative = "win",
		win = M.win_id,
		row = M.header_height or 2,
		col = 2,
		width = p_w,
		height = 1,
		style = "minimal",
		border = "rounded",
		zindex = 60,
		title = string.format(" %s Search YouTube ", theme.icon("search")),
		title_pos = "left",
	}
	if vim.fn.has("nvim-0.10") == 1 then
		config.footer = utils.safe_truncate(" Enter Search · Tab Results · Esc Normal ", p_w)
		config.footer_pos = "right"
	end
	local p_win = vim.api.nvim_open_win(M.search_prompt_buf, focus == true, config)

	M.search_prompt_win = p_win
	vim.wo[p_win].winhighlight = "Normal:YtPlayerNormal,NormalNC:YtPlayerNormal,NormalFloat:YtPlayerNormal,FloatBorder:YtPlayerBorder,FloatTitle:YtPlayerTitle,FloatFooter:YtPlayerKeyHint"
	vim.wo[p_win].wrap = false
	vim.wo[p_win].number = false
	vim.wo[p_win].relativenumber = false
	vim.wo[p_win].signcolumn = "no"
	vim.wo[p_win].list = false

	local po = { buffer = M.search_prompt_buf, silent = true, noremap = true }
	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		buffer = M.search_prompt_buf,
		callback = function(event)
			M.search_draft = vim.api.nvim_buf_get_lines(event.buf, 0, 1, false)[1] or ""
		end,
	})

	local function submit_search()
		local lines = vim.api.nvim_buf_get_lines(M.search_prompt_buf, 0, 1, false)
		local q = vim.trim(lines[1] or "")
		if q ~= "" then
			M.run_search(q)
		end
		if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
			vim.cmd("stopinsert")
			vim.api.nvim_set_current_win(M.win_id)
			M.focus_selection()
		end
	end

	vim.keymap.set({ "n", "i" }, "<CR>", submit_search, po)

	local function jump_to_results()
		if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
			vim.cmd("stopinsert")
			vim.api.nvim_set_current_win(M.win_id)
			M.focus_selection()
		end
	end

	vim.keymap.set({ "n", "i" }, "<Down>", jump_to_results, po)
	vim.keymap.set({ "n", "i" }, "<C-j>", jump_to_results, po)
	vim.keymap.set({ "n", "i" }, "<Tab>", jump_to_results, po)
	vim.keymap.set("n", "j", jump_to_results, po)

	vim.keymap.set("n", "<Esc>", function()
		if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
			vim.api.nvim_set_current_win(M.win_id)
		end
	end, po)

	vim.keymap.set("n", "q", function()
		M.close()
	end, po)

	if focus then
		vim.cmd("startinsert!")
	end
end

--- Close the embedded search prompt window
function M.close_search_prompt()
	if M.search_prompt_buf and vim.api.nvim_buf_is_valid(M.search_prompt_buf) then
		M.search_draft = vim.api.nvim_buf_get_lines(M.search_prompt_buf, 0, 1, false)[1] or ""
	end
	if M.search_prompt_win and vim.api.nvim_win_is_valid(M.search_prompt_win) then
		pcall(vim.api.nvim_win_close, M.search_prompt_win, true)
	end
	M.search_prompt_win = nil
end

--- Get the selected item independently of the current viewport.
local function get_selected_index()
	local state = state_mod.get_current()
	if M.active_tab == 1 or M.active_tab == 3 then
		local index = M.selection[M.active_tab]
		return index, (state.playlist or {})[index]
	elseif M.active_tab == 2 then
		return M.search_selected_idx, M.search_results[M.search_selected_idx]
	elseif M.active_tab == 4 then
		local name = M.playlist_names[M.selected_pl_idx]
		if M.playlist_col == 2 then
			local tracks = name and require("yt-player.playlists").get_all()[name] or {}
			return M.selected_pl_track_idx, (tracks or {})[M.selected_pl_track_idx], name
		end
		return M.selected_pl_idx, name
	elseif M.active_tab == 5 then
		local index = M.selection[5]
		return index, require("yt-player.history").get()[index]
	end
end

local function item_count()
	if M.active_tab == 1 or M.active_tab == 3 then
		return #(state_mod.get_current().playlist or {})
	elseif M.active_tab == 2 then
		return #M.search_results
	elseif M.active_tab == 4 then
		if M.playlist_col == 1 then return #M.playlist_names end
		local name = M.playlist_names[M.selected_pl_idx]
		return #(name and require("yt-player.playlists").get_all()[name] or {})
	end
	return #require("yt-player.history").get()
end

function M.focus_selection()
	if not M.win_id or not vim.api.nvim_win_is_valid(M.win_id) then return end
	local index = get_selected_index()
	local column = M.active_tab == 4 and M.playlist_col or 1
	local row = M.item_rows[column][index]
	if not row then row = math.min(3, vim.api.nvim_buf_line_count(M.buf_id)) end
	local col = 0
	if column == 2 and vim.api.nvim_win_get_width(M.win_id) >= 80 then
		col = (M.pane_columns or {})[row] or 0
	end
	pcall(vim.api.nvim_win_set_cursor, M.win_id, { row, col })
end

function M.select(index)
	index = math.max(1, math.min(index, math.max(1, item_count())))
	if M.active_tab == 2 then M.search_selected_idx = index
	elseif M.active_tab == 4 then
		if M.playlist_col == 1 then
			if M.selected_pl_idx ~= index then M.selected_pl_track_idx = 1 end
			M.selected_pl_idx = index
		else M.selected_pl_track_idx = index end
	else M.selection[M.active_tab] = index end
	M.refresh()
end

function M.switch_tab(index)
	M.active_tab = index
	M.playlist_col = 1
	M.refresh()
	if index == 2 then M.ensure_search_prompt(true) end
end

local hints = {
	" [Space] Pause  [/] Search  [Enter] Play  [?] Help  [q] Close ",
	" [Enter] Play  [a] Queue  [s] Save  [i] Search  [L] More  [?] Help ",
	" [Enter] Play  [J/K] Move  [dd] Remove  [S] Shuffle  [?] Help ",
	" [Tab] Pane  [Enter] Play  [a] Queue  [N] New  [?] Help ",
	" [Enter] Replay  [a] Queue  [s] Save  [?] Help  [q] Close ",
}

--- Render one bounded viewport, keeping tabs and search input visible.
function M.refresh()
	if not M.win_id or not vim.api.nvim_win_is_valid(M.win_id) then return end
	local index = get_selected_index() or 1
	local count = item_count()
	index = math.max(1, math.min(index, math.max(1, count)))
	if M.active_tab == 2 then M.search_selected_idx = index
	elseif M.active_tab ~= 4 then M.selection[M.active_tab] = index end
	local width = vim.api.nvim_win_get_width(M.win_id)
	local height = vim.api.nvim_win_get_height(M.win_id)
	local lines, highlights, rows, indices = views.render(M, width, height)
	M.item_rows, M.row_indices = rows, indices
	window.render(M.buf_id, lines, highlights)
	local footer = width >= 64 and hints[M.active_tab] or " [/] Search  [?] Help  [q] Close "
	window.set_footer(M.win_id, footer)
	M.focus_selection()
	vim.api.nvim_win_call(M.win_id, function()
		vim.fn.winrestview({ topline = 1, leftcol = 0 })
	end)
	if M.active_tab == 2 then M.ensure_search_prompt(false) else M.close_search_prompt() end
end

function M.show_help()
	if M.help then window.safe_close(M.help.win, M.help.buf); M.help = nil; return end
	local lines = {
		"  NAVIGATION",
		"  1–5 / Tab / Shift-Tab   Switch tabs / playlist panes",
		"  j/k / arrows            Select a track or playlist",
		"  Ctrl-d/u / PageDown/Up  Move a page",
		"  gg / G                  First / last item",
		"  / / i                   Focus YouTube search",
		"",
		"  PLAYBACK",
		"  Space / p               Toggle play / pause",
		"  n / b                   Next / previous track",
		"  h/l                     Seek 5s (playlist pane: switch pane)",
		"  +/- / m                 Adjust volume / mute",
		"  < / >                   Adjust playback speed",
		"  r / R / v               Toggle radio / repeat / visualizer",
		"",
		"  SELECTION",
		"  Enter                   Play selected track / playlist",
		"  a                       Queue selection (Deck/Queue: save)",
		"  s                       Save selected track to a playlist",
		"  dd                      Remove queue / playlist selection",
		"  J/K / S                 Move queue track / shuffle queue",
		"  L                       Load more search results",
		"  N / r                   Create / rename a playlist",
		"",
		"  q / Esc                 Close this window",
	}
	M.help = window.open_float({ width = 66, height = #lines, title = " Player shortcuts ", enter = true, zindex = 70 })
	local help = M.help
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = help.buf, once = true,
		callback = function()
			window.forget(help.win, help.buf)
			if M.help == help then M.help = nil end
		end,
	})
	for index, line in ipairs(lines) do lines[index] = utils.safe_truncate(line, vim.api.nvim_win_get_width(M.help.win)) end
	window.render(M.help.buf, lines)
	for _, key in ipairs({ "q", "<Esc>", "?" }) do
		vim.keymap.set("n", key, function()
			if M.help then window.safe_close(M.help.win, M.help.buf); M.help = nil end
		end, { buffer = M.help.buf, silent = true })
	end
end

local function save_playlists(lists, name)
	local path = vim.fn.stdpath("data") .. "/yt-player-playlists.json"
	if not utils.atomic_write_json(path, lists) then
		vim.notify("YT Player: Could not save playlists", vim.log.levels.ERROR)
		return false
	end
	local names = vim.tbl_keys(lists)
	table.sort(names)
	M.selected_pl_idx = math.max(1, vim.fn.index(names, name) + 1)
	M.selected_pl_track_idx = 1
	M.refresh()
	return true
end

local function setup_hub_keymaps()
	local o = { buffer = M.buf_id, silent = true, noremap = true }

	vim.keymap.set("n", "q", M.close, o)
	vim.keymap.set("n", "<Esc>", M.close, o)

	-- Navigation moves through data, never through headings or empty rows.
	for i = 1, 5 do
		vim.keymap.set("n", tostring(i), function() M.switch_tab(i) end, o)
	end
	local function move(delta)
		return function() M.select((get_selected_index() or 1) + delta) end
	end
	for _, key in ipairs({ "j", "<Down>" }) do vim.keymap.set("n", key, move(1), o) end
	for _, key in ipairs({ "k", "<Up>" }) do vim.keymap.set("n", key, move(-1), o) end
	for _, pair in ipairs({ { "<C-d>", 1 }, { "<PageDown>", 1 }, { "<C-u>", -1 }, { "<PageUp>", -1 } }) do
		vim.keymap.set("n", pair[1], function()
			local page = math.max(1, math.floor(vim.api.nvim_win_get_height(M.win_id) / 2))
			M.select((get_selected_index() or 1) + pair[2] * page)
		end, o)
	end
	vim.keymap.set("n", "gg", function() M.select(1) end, o)
	vim.keymap.set("n", "G", function() M.select(item_count()) end, o)
	vim.keymap.set("n", "<Tab>", function()
		if M.active_tab == 4 and M.playlist_col == 1 then M.playlist_col = 2; M.refresh()
		else M.switch_tab(M.active_tab % #TABS + 1) end
	end, o)
	vim.keymap.set("n", "<S-Tab>", function()
		if M.active_tab == 4 and M.playlist_col == 2 then M.playlist_col = 1; M.refresh()
		else M.switch_tab((M.active_tab - 2 + #TABS) % #TABS + 1) end
	end, o)
	vim.keymap.set("n", "?", M.show_help, o)
	local function playback(command)
		return function()
			require("yt-player").command(command)
			vim.defer_fn(M.refresh, 150)
		end
	end
	vim.keymap.set("n", "p", playback({ "cycle", "pause" }), o)
	vim.keymap.set("n", "m", playback({ "cycle", "mute" }), o)
	vim.keymap.set("n", ">", playback({ "add", "speed", 0.25 }), o)
	vim.keymap.set("n", "<", playback({ "add", "speed", -0.25 }), o)
	for _, pair in ipairs({ { "h", -5, 1 }, { "l", 5, 2 } }) do
		vim.keymap.set("n", pair[1], function()
			if M.active_tab == 4 then M.playlist_col = pair[3]; M.refresh()
			else playback({ "seek", pair[2], "relative" })() end
		end, o)
	end
	vim.keymap.set("n", "v", function() visualizer.cycle_style(); M.refresh() end, o)
	vim.keymap.set("n", "S", function()
		if M.active_tab == 1 or M.active_tab == 3 then playback({ "playlist-shuffle" })() end
	end, o)
	vim.keymap.set("n", "R", function()
		local state = state_mod.get_current()
		if state.loop_file and state.loop_file ~= "no" then
			require("yt-player").command({ "set_property", "loop-file", "no" })
			require("yt-player").command({ "set_property", "loop-playlist", "inf" })
		elseif state.loop_playlist and state.loop_playlist ~= "no" then
			require("yt-player").command({ "set_property", "loop-playlist", "no" })
		else require("yt-player").command({ "set_property", "loop-file", "inf" }) end
		vim.defer_fn(M.refresh, 150)
	end, o)
	vim.keymap.set("n", "s", function()
		local _, item = get_selected_index()
		if type(item) == "table" and (item.url or item.filename) then
			require("yt-player.playlists").prompt_save({
				url = item.url or item.filename, title = utils.resolve_title(item),
				duration = item.duration, channel = item.channel,
			})
		end
	end, o)

	-- Essential Playback Controls
	vim.keymap.set("n", "<Space>", function()
		require("yt-player").command({ "cycle", "pause" })
		vim.defer_fn(M.refresh, 150)
	end, o)

	vim.keymap.set("n", "n", function()
		require("yt-player").command({ "playlist-next", "weak" })
		vim.defer_fn(M.refresh, 300)
	end, o)

	vim.keymap.set("n", "b", function()
		require("yt-player").command({ "playlist-prev", "weak" })
		vim.defer_fn(M.refresh, 300)
	end, o)

	vim.keymap.set("n", "+", function()
		require("yt-player").command({ "add", "volume", 5 })
		vim.defer_fn(M.refresh, 150)
	end, o)

	vim.keymap.set("n", "-", function()
		require("yt-player").command({ "add", "volume", -5 })
		vim.defer_fn(M.refresh, 150)
	end, o)

	-- Search Input trigger 'i' or '/': Focuses search prompt bar
	local function focus_search_prompt()
		if M.active_tab ~= 2 then
			M.active_tab = 2
			M.refresh()
		end
		M.ensure_search_prompt(true)
	end
	vim.keymap.set("n", "i", focus_search_prompt, o)
	vim.keymap.set("n", "/", focus_search_prompt, o)

	-- Action key '<CR>' (Contextual per tab)
	vim.keymap.set("n", "<CR>", function()
		if M.active_tab == 1 or M.active_tab == 3 then
			local idx, item = get_selected_index()
			if item then
				require("yt-player.mpv").send_command({ "playlist-play-index", idx - 1 })
				vim.defer_fn(M.refresh, 250)
			end
		elseif M.active_tab == 2 then
			local _, item = get_selected_index()
			if item and item.url then
				require("yt-player").load(item.url)
				require("yt-player.history").add(item)
				local clean_t = utils.resolve_title(item)
				vim.notify(string.format("YT Player: Playing '%s'", utils.safe_truncate(clean_t, 40)), vim.log.levels.INFO)
				vim.defer_fn(M.refresh, 300)
			else
				M.ensure_search_prompt(true)
			end
		elseif M.active_tab == 4 then
			local _, item = get_selected_index()
			if M.playlist_col == 1 and item and type(item) == "string" then
				require("yt-player.playlists").play_all(item)
				vim.defer_fn(M.refresh, 350)
			elseif M.playlist_col == 2 and item and item.url then
				require("yt-player").load(item.url)
				vim.defer_fn(M.refresh, 350)
			end
		elseif M.active_tab == 5 then
			local _, hist_item = get_selected_index()
			if hist_item and hist_item.url then
				require("yt-player").load(hist_item.url)
				vim.defer_fn(M.refresh, 350)
			end
		end
	end, o)

	-- Append / Save key 'a'
	local function append_selection()
		if M.active_tab == 1 or M.active_tab == 3 then
			local _, item = get_selected_index()
			if item then
				local clean_t = utils.resolve_title(item)
				require("yt-player.playlists").prompt_save({
					url = item.filename or item.url,
					title = clean_t,
					duration = item.duration,
				})
			end
		elseif M.active_tab == 2 then
			local _, item = get_selected_index()
			if item and item.url then
				require("yt-player").queue(item, true)
				local clean_t = utils.resolve_title(item)
				vim.notify(string.format("YT Player: Queued '%s'", utils.safe_truncate(clean_t, 35)), vim.log.levels.INFO)
				vim.defer_fn(M.refresh, 200)
			end
		elseif M.active_tab == 4 then
			local _, item = get_selected_index()
			if M.playlist_col == 1 and item and type(item) == "string" then
				require("yt-player.playlists").queue_all(item)
				vim.defer_fn(M.refresh, 250)
			elseif M.playlist_col == 2 and item and item.url then
				require("yt-player").queue(item, true)
				vim.defer_fn(M.refresh, 250)
			end
		elseif M.active_tab == 5 then
			local _, hist_item = get_selected_index()
			if hist_item and hist_item.url then
				require("yt-player").queue(hist_item, true)
				vim.defer_fn(M.refresh, 250)
			end
		end
	end
	for _, key in ipairs({ "a", "A", "<C-a>" }) do vim.keymap.set("n", key, append_selection, o) end

	-- Load more search results 'L' on Search tab
	vim.keymap.set("n", "L", function()
		if M.active_tab == 2 then
			M.load_more_search()
		end
	end, o)

	-- Remove only after a complete dd command.
	vim.keymap.set("n", "dd", function()
		if M.active_tab == 1 or M.active_tab == 3 then
			local idx, item = get_selected_index()
			if item then
				require("yt-player.mpv").send_command({ "playlist-remove", idx - 1 })
				vim.defer_fn(M.refresh, 200)
			end
		elseif M.active_tab == 4 then
			local _, item, parent_pl = get_selected_index()
			if M.playlist_col == 1 and item and type(item) == "string" then
				vim.ui.select({ "Cancel", "Delete playlist" }, { prompt = "Delete “" .. item .. "”?" }, function(choice)
					if choice == "Delete playlist" then
						require("yt-player.playlists").remove_something(item)
						M.refresh()
					end
				end)
			elseif M.playlist_col == 2 and item and parent_pl then
				require("yt-player.playlists").remove_something(parent_pl, item.url)
				vim.notify("YT Player: Removed track from playlist", vim.log.levels.INFO)
				vim.defer_fn(M.refresh, 150)
			end
		end
	end, o)

	-- Keep the moved track selected after mpv updates its queue.
	for _, pair in ipairs({ { "J", 1 }, { "K", -1 } }) do
		vim.keymap.set("n", pair[1], function()
			if M.active_tab ~= 1 and M.active_tab ~= 3 then return end
			local index, item = get_selected_index()
			local target = index + pair[2]
			if item and target >= 1 and target <= item_count() then
				local tab = M.active_tab
				require("yt-player.mpv").send_command({ "playlist-move", index - 1, pair[2] > 0 and index + 1 or index - 2 })
				M.selection[tab] = target
				vim.defer_fn(M.refresh, 150)
			end
		end, o)
	end

	-- New playlist 'N' on Playlists tab
	vim.keymap.set("n", "N", function()
		if M.active_tab == 4 then
			vim.ui.input({ prompt = "New Playlist Name: " }, function(input)
				if input and vim.trim(input) ~= "" then
					local pl_mod = require("yt-player.playlists")
					local lists = pl_mod.get_all()
					local name = vim.trim(input)
					if lists[name] then
						vim.notify("YT Player: A playlist with that name already exists", vim.log.levels.WARN)
						return
					end
					lists[name] = {}
					if save_playlists(lists, name) then
						vim.notify(string.format("YT Player: Created playlist '%s'", name), vim.log.levels.INFO)
					end
				end
			end)
		end
	end, o)

	-- Rename playlist 'r' on Playlists tab
	vim.keymap.set("n", "r", function()
		if M.active_tab == 4 then
			local _, pl_name = get_selected_index()
			if pl_name and type(pl_name) == "string" then
				vim.ui.input({ prompt = "Rename playlist: ", default = pl_name }, function(input)
					if input and vim.trim(input) ~= "" and vim.trim(input) ~= pl_name then
						local pl_mod = require("yt-player.playlists")
						local lists = pl_mod.get_all()
						if lists[vim.trim(input)] then
							vim.notify("YT Player: A playlist with that name already exists", vim.log.levels.WARN)
							return
						end
						lists[vim.trim(input)] = lists[pl_name]
						lists[pl_name] = nil
						if save_playlists(lists, vim.trim(input)) then
							vim.notify(string.format("YT Player: Renamed to '%s'", vim.trim(input)), vim.log.levels.INFO)
						end
					end
				end)
			end
		else
			require("yt-player.radio").toggle()
			M.refresh()
		end
	end, o)
end

--- Open the UI Hub without losing the current search or tab selection.
---@param tab_idx number|nil
---@param search_query string|nil
function M.open(tab_idx, search_query)
	if tab_idx and tab_idx >= 1 and tab_idx <= #TABS then M.active_tab = tab_idx end
	local query = vim.trim(search_query or "")
	if query ~= "" then M.active_tab = 2 end
	if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
		vim.api.nvim_set_current_win(M.win_id)
		M.refresh()
		if query ~= "" then M.run_search(query)
		elseif M.active_tab == 2 then M.ensure_search_prompt(true) end
		return
	end
	local ui_config = require("yt-player").config.ui or {}
	if M.visualizer_config ~= ui_config.visualizer then
		visualizer.current_style = ui_config.visualizer or "wave"
		M.visualizer_config = ui_config.visualizer
	end
	local info = window.open_float({
		width = math.min(144, math.floor(vim.o.columns * 0.94)),
		height = math.min(44, math.floor(vim.o.lines * 0.92)),
		title = " " .. theme.icon("music") .. " YT PLAYER ",
		border = ui_config.border, cursorline = true,
	})
	M.win_id, M.buf_id = info.win, info.buf
	vim.bo[M.buf_id].filetype = "yt-player-ui"
	vim.wo[M.win_id].scrolloff = 0
	vim.wo[M.win_id].sidescrolloff = 0
	setup_hub_keymaps()
	M.refresh()
	if query ~= "" then M.run_search(query)
	elseif M.active_tab == 2 then M.ensure_search_prompt(true) end

	local group = vim.api.nvim_create_augroup("YTPlayerHub", { clear = true })
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group, buffer = M.buf_id,
		callback = function()
			if not M.win_id or not vim.api.nvim_win_is_valid(M.win_id) then return end
			local cursor = vim.api.nvim_win_get_cursor(M.win_id)
			local column = M.active_tab == 4 and M.playlist_col or 1
			if M.active_tab == 4 and vim.api.nvim_win_get_width(M.win_id) >= 80 then
				local finish = (M.pane_columns or {})[cursor[1]]
				if finish then column = cursor[2] >= finish and 2 or 1 end
				M.playlist_col = column
			end
			local index = M.row_indices[column][cursor[1]]
			if index and index ~= get_selected_index() then M.select(index) end
		end,
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			if not M.win_id or not vim.api.nvim_win_is_valid(M.win_id) then return end
			window.resize(M.win_id, math.min(144, math.floor(vim.o.columns * 0.94)), math.min(44, math.floor(vim.o.lines * 0.92)))
			if M.help and vim.api.nvim_win_is_valid(M.help.win) then
				window.resize(M.help.win, 66, vim.api.nvim_buf_line_count(M.help.buf))
			end
			M.refresh()
		end,
	})
	M.update_timer = uv.new_timer()
	M.update_timer:start(250, 250, vim.schedule_wrap(function()
		if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then M.refresh() else M.close() end
	end))
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group, buffer = M.buf_id, once = true,
		callback = function() M.close(true) end,
	})
end

local is_closing = false
function M.close(wiping)
	if is_closing then return end
	is_closing = true
	M.search_generation = M.search_generation + 1
	M.search_loading, M.search_loading_more = false, false
	M.close_search_prompt()
	if M.search_prompt_buf and vim.api.nvim_buf_is_valid(M.search_prompt_buf) then
		pcall(vim.api.nvim_buf_delete, M.search_prompt_buf, { force = true })
	end
	M.search_prompt_buf = nil
	if M.help then window.safe_close(M.help.win, M.help.buf); M.help = nil end
	if M.update_timer then
		M.update_timer:stop()
		M.update_timer:close()
		M.update_timer = nil
	end
	local win, buf = M.win_id, M.buf_id
	M.win_id, M.buf_id = nil, nil
	if wiping then window.forget(win, buf) else window.safe_close(win, buf) end
	pcall(vim.api.nvim_del_augroup_by_name, "YTPlayerHub")
	is_closing = false
end

function M.toggle(tab_idx, search_query)
	if M.win_id and vim.api.nvim_win_is_valid(M.win_id) and (not tab_idx or tab_idx == M.active_tab) and not search_query then
		M.close()
	else M.open(tab_idx, search_query) end
end

return M
