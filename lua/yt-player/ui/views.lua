---@mod yt-player.ui.views Responsive views for the music hub
local M = {}
local utils = require("yt-player.utils")
local theme = require("yt-player.ui.theme")
local layout = require("yt-player.ui.layout")
local progress = require("yt-player.ui.components.progress")
local visualizer = require("yt-player.ui.components.visualizer")
local deck = require("yt-player.ui.components.deck")

local tabs = { "Deck", "Search", "Queue", "Playlists", "History" }

local function duration(item)
	local value = tonumber(item.duration or item.length_sec)
	return value and value > 0 and utils.format_time(value) or ""
end

local function relative_time(timestamp)
	local age = math.max(0, os.time() - (tonumber(timestamp) or os.time()))
	if age < 60 then return "just now" end
	if age < 3600 then return math.floor(age / 60) .. "m ago" end
	if age < 86400 then return math.floor(age / 3600) .. "h ago" end
	return math.floor(age / 86400) .. "d ago"
end

function M.render(hub, width, height)
	local state = require("yt-player.state").get_current()
	local active_item = (state.playlist or {})[(state.playlist_pos or 0) + 1]
	local active_url = active_item and (active_item.filename or active_item.url)
	local function is_current(item)
		return active_url ~= nil and (item.url or item.filename) == active_url
	end
	local lines, highlights = {}, {}
	local rows = { {}, {} }
	local indices = { {}, {} }
	local content_width = math.max(1, width - 4)
	local rich_shell = height >= 16 and width >= 52
	local show_transport = rich_shell
	if show_transport then height = height - 2 end
	hub.pane_columns = {}
	local legacy_footer = vim.fn.has("nvim-0.10") == 0
	if legacy_footer then height = height - 1 end
	local function highlight(line, group, first, last)
		table.insert(highlights, { line = line - 1, hl = group, col_start = first or 0, col_end = last or -1 })
	end
	local function add(text, group)
		table.insert(lines, utils.safe_truncate(text or "", width))
		if group then highlight(#lines, group) end
	end
	local function body(text, group)
		add("  " .. (text or ""), group)
		if group == "YtPlayerFrame" and text then
			local label = text:match("^╭─ (.-) ─")
			if label then highlight(#lines, "YtPlayerAccent", #"  ╭─ ", #"  ╭─ " + #label) end
		end
	end
	local function panel(text, group)
		body(layout.inset(text, content_width), "YtPlayerFrame")
		highlight(#lines, group or "YtPlayerText", #"  │ ", #lines[#lines] - #" │")
	end
	local function split_panel(left, right, left_width, right_width, left_group, right_group)
		local left_cell = layout.fit(left, left_width)
		panel(left_cell .. " │ " .. layout.fit(right, right_width))
		local start = #"  │ " + #left_cell
		highlight(#lines, left_group or "YtPlayerText", #"  │ ", start)
		highlight(#lines, "YtPlayerFrame", start, start + #" │ ")
		highlight(#lines, right_group or "YtPlayerText", start + #" │ ", #lines[#lines] - #" │")
		hub.pane_columns[#lines] = start + #" │ "
	end
	local function divider()
		body(string.rep("─", content_width), "YtPlayerSeparator")
	end
	local function map_row(column, index)
		rows[column][index] = #lines
		indices[column][#lines] = index
	end
	local function selected_marker(selected, playing)
		return selected and theme.icon("selected") or (playing and theme.icon("playing") or " ")
	end
	local function track(item, index, pane_width, selected, metadata, current)
		local marker = selected_marker(selected, current)
		return layout.track(index, utils.resolve_title(item, state), metadata, pane_width, marker)
	end
	local function track_metadata(item)
		local artist = item.channel or (state.artist_map or {})[item.filename or item.url] or ""
		return width >= 100 and layout.pair(artist, duration(item), 28):gsub("%s+$", "") or duration(item)
	end
	local function list(items, selected, render_row, boxed)
		local capacity = math.max(1, height - #lines - 1)
		local first, last = layout.viewport(#items, selected, capacity)
		for index = first, last do
			local text, group = render_row(items[index], index, index == selected)
			body(boxed and layout.inset(text, content_width) or text, boxed and "YtPlayerFrame" or group)
			if boxed then
				local line = lines[#lines]
				highlight(#lines, index == selected and "YtPlayerSelected" or group, #"  │ ", #line - #" │")
				highlight(#lines, "YtPlayerDuration", math.max(#"  │ ", #line - #" │" - 7), #line - #" │")
			end
			map_row(1, index)
		end
		if #items > 0 then
			if boxed then
				while #lines < height - 1 do panel("") end
			end
			local range = string.format("%d–%d of %d", first, last, #items)
			body(boxed and layout.rule(content_width, range, "j/k SELECT", true) or layout.pair(range, "j/k Select", content_width), boxed and "YtPlayerFrame" or "YtPlayerMuted")
		end
	end
	if width < 24 or height < 8 then
		add("YouTube Player", "YtPlayerTitleText")
		if height >= 2 then add("Enlarge terminal to continue", "YtPlayerMuted") end
		return lines, highlights, rows, indices
	end

	local function render_queue(queue, selected, hints)
		local total = 0
		for _, item in ipairs(queue) do total = total + (tonumber(item.duration or item.length_sec) or 0) end
		local summary = #queue .. " TRACKS" .. (total > 0 and " · " .. utils.format_time(total) or "")
		body(layout.rule(content_width, "PLAYBACK QUEUE", summary), "YtPlayerFrame")
		if hints then body(layout.inset("Enter Play   J/K Move   dd Remove   S Shuffle", content_width), "YtPlayerKeyHint") end
		local inner = math.max(1, content_width - 4)
		body(layout.inset(layout.track_columns(nil, "TITLE", "ARTIST", "TIME", inner), content_width), "YtPlayerMuted")
		if #queue == 0 then
			body(layout.inset("Your queue is empty.", content_width), "YtPlayerMuted")
			body(layout.inset("/ Search   ·   a Add a track to queue", content_width), "YtPlayerKeyHint")
			while #lines < height - 1 do panel("") end
			body(layout.rule(content_width, nil, nil, true), "YtPlayerFrame")
		else
			list(queue, selected, function(item, index, is_selected)
				local current = index == (state.playlist_pos or 0) + 1
				local artist = item.channel or (state.artist_map or {})[item.filename or item.url] or ""
				local row = layout.track_columns(index, utils.resolve_title(item, state), artist, duration(item), inner, selected_marker(is_selected, current))
				return row, current and "YtPlayerPlaying" or "YtPlayerText"
			end, true)
		end
	end

	if rich_shell then
		local status = state.playing and "● PLAYING" or (state.title and state.title ~= "" and "Ⅱ PAUSED" or "○ READY")
		body(layout.pair("♫ YT PLAYER  /  MUSIC STATION", status, content_width), "YtPlayerBrand")
	end
	-- Full labels on roomy terminals, short labels on compact terminals.
	local labels = {}
	for index, name in ipairs(tabs) do
		local count = index == 2 and #hub.search_results or (index == 3 and #(state.playlist or {}) or 0)
		labels[index] = string.format(" [%d] %s%s ", index, string.upper(name), count > 0 and " · " .. count or "")
	end
	if vim.fn.strdisplaywidth(table.concat(labels, " ")) > content_width then
		for index, name in ipairs(tabs) do labels[index] = string.format(" %d %s ", index, name) end
	end
	if vim.fn.strdisplaywidth(table.concat(labels, " ")) > content_width then
		for index in ipairs(tabs) do labels[index] = " " .. index .. " " end
	end
	local header = "  "
	local nav_row = #lines + 1
	for index, label in ipairs(labels) do
		local start = #header
		header = header .. label .. " "
		highlight(nav_row, index == hub.active_tab and "YtPlayerTabActive" or "YtPlayerTabInactive", start, #header - 1)
	end
	add(header)
	divider()
	hub.header_height = #lines

	if hub.active_tab == 1 and height >= 15 then
		local panel_lines, panel_highlights = deck.render(state, content_width, { tall = height >= 26 })
		local offset = #lines
		for _, line in ipairs(panel_lines) do body(line) end
		for _, mark in ipairs(panel_highlights) do
			highlight(mark.line + offset + 1, mark.hl, (mark.col_start or 0) + 2, mark.col_end == -1 and -1 or mark.col_end + 2)
		end
		render_queue(state.playlist or {}, hub.selection[1])
	elseif hub.active_tab == 1 then
		local has_track = state.title and state.title ~= ""
		local status = state.playing and "PLAYING" or (has_track and "PAUSED" or "READY")
		if height >= 14 then body(layout.pair("NOW PLAYING", status, content_width), "YtPlayerAccent") end
		body(has_track and utils.resolve_title(state.title, state) or "Your next listening session starts here", "YtPlayerTitleText")
		if height >= 12 then body(has_track and (state.artist or "Unknown artist") or "Press / to find music, podcasts, and live streams.", "YtPlayerArtist") end
		if height >= 18 then body() end
		local elapsed = utils.format_time(state.position)
		local total = (state.duration or 0) > 0 and utils.format_time(state.duration) or "--:--"
		local bar = progress.bar(state.position, state.duration, math.max(1, content_width - #elapsed - #total - 2), "slider")
		body(elapsed .. " " .. bar .. " " .. total, "YtPlayerProgress")
		if height >= 24 and width >= 60 and visualizer.current_style ~= "none" then
			body(visualizer.next_frame(visualizer.current_style, state.playing), "YtPlayerActive")
		end
		local repeat_mode = state.loop_file and state.loop_file ~= "no" and "Track"
			or (state.loop_playlist and state.loop_playlist ~= "no" and "Queue" or "Off")
		local telemetry = string.format("%s  ·  %.2fx", state.muted and "Muted" or string.format("Vol %d%%", state.volume or 100), state.speed or 1)
		if width >= 64 then telemetry = telemetry .. "  ·  Radio " .. (state.radio_enabled and "on" or "off") .. "  ·  Repeat " .. repeat_mode end
		if height >= 14 then body(telemetry, "YtPlayerMuted") end
		if height >= 12 then divider() end
		local queue = state.playlist or {}
		body(layout.pair("UP NEXT", #queue .. " tracks", content_width), "YtPlayerAccent")
		if #queue == 0 then
			body("Your queue is empty.", "YtPlayerMuted")
			body("/ Search   ·   a Add a search result to queue", "YtPlayerKeyHint")
		else
			list(queue, hub.selection[1], function(item, index, selected)
				local current = index == (state.playlist_pos or 0) + 1
				return track(item, index, content_width, selected, track_metadata(item), current), current and "YtPlayerPlaying" or "YtPlayerText"
			end)
		end
	elseif hub.active_tab == 2 then
		-- Reserve three lines for the child search input and its border.
		add(); add(); add()
		local status, group = "Search for something you want to hear.", "YtPlayerMuted"
		if hub.search_loading or hub.search_loading_more then
			local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
			hub.spinner_idx = hub.spinner_idx % #frames + 1
			status = frames[hub.spinner_idx] .. (hub.search_loading and " Searching for “" or " Loading more for “") .. hub.search_query .. "”…"
			group = "YtPlayerWarning"
		elseif hub.search_error then
			status, group = hub.search_error, "YtPlayerError"
		elseif #hub.search_results > 0 then
			status, group = #hub.search_results .. " results for “" .. hub.search_query .. "”", "YtPlayerAccent"
		elseif hub.search_query ~= "" then
			status = "No results. Try a different artist or track name."
		end
		body(status, group)
		local boxed = height >= 12
		if #hub.search_results > 0 then
			if boxed then body(layout.rule(content_width, "SEARCH RESULTS", "Enter PLAY · a QUEUE · s SAVE"), "YtPlayerFrame")
			elseif height >= 14 then divider() end
			local inner = boxed and content_width - 4 or content_width
			local split = width >= 96 and height >= 18
			local left_width = split and math.floor((inner - 3) * 0.58) or inner
			local right_width = inner - left_width - 3
			local details = {}
			local item = hub.search_results[hub.search_selected_idx]
			if split and item then
				table.insert(details, "TRACK DETAILS")
				table.insert(details, "")
				for _, line in ipairs(layout.wrap(utils.resolve_title(item, state), right_width, 3)) do table.insert(details, line) end
				table.insert(details, "")
				table.insert(details, item.channel or "Unknown channel")
				table.insert(details, "DURATION  " .. (duration(item) ~= "" and duration(item) or "LIVE / UNKNOWN"))
				if item.upload_date then table.insert(details, "UPLOADED  " .. item.upload_date) end
				table.insert(details, "")
				table.insert(details, "[Enter] Play now")
				table.insert(details, "[a] Add to queue")
				table.insert(details, "[s] Save to playlist")
			end
			local capacity = math.max(1, height - #lines - 1)
			local first, last = layout.viewport(#hub.search_results, hub.search_selected_idx, capacity)
			for offset = 1, boxed and capacity or math.min(capacity, math.max(last - first + 1, #details)) do
				local index = first + offset - 1
				local result = index <= last and hub.search_results[index]
				local left = result and track(result, index, left_width, index == hub.search_selected_idx, duration(result), is_current(result)) or ""
				local group = index == hub.search_selected_idx and "YtPlayerSelected" or (result and is_current(result) and "YtPlayerPlaying" or "YtPlayerText")
				if split then
					split_panel(left, details[offset] or "", left_width, right_width, group, offset <= 5 and "YtPlayerTitleText" or "YtPlayerMuted")
				elseif boxed then panel(left, group)
				else body(left, group) end
				if result then map_row(1, index) end
			end
			local range = string.format("%d–%d of %d", first, last, #hub.search_results)
			local more = hub.search_has_more and "L MORE RESULTS" or "END OF RESULTS"
			body(boxed and layout.rule(content_width, range, more, true) or layout.pair(range, more, content_width), boxed and "YtPlayerFrame" or "YtPlayerMuted")
		elseif not hub.search_loading then
			body("i Edit query   ·   Enter Search", "YtPlayerKeyHint")
		end
	elseif hub.active_tab == 3 then
		render_queue(state.playlist or {}, hub.selection[3], true)
	elseif hub.active_tab == 4 then
		local playlists = require("yt-player.playlists").get_all()
		hub.playlist_names = vim.tbl_keys(playlists)
		table.sort(hub.playlist_names)
		hub.selected_pl_idx = math.max(1, math.min(hub.selected_pl_idx, #hub.playlist_names))
		local name = hub.playlist_names[hub.selected_pl_idx]
		local tracks = name and playlists[name] or {}
		hub.selected_pl_track_idx = math.max(1, math.min(hub.selected_pl_track_idx, #tracks))
		local boxed = height >= 12
		local inner = boxed and content_width - 4 or content_width
		body(boxed and layout.rule(content_width, "LOCAL PLAYLISTS", #hub.playlist_names .. " SAVED") or layout.pair("LOCAL PLAYLISTS", #hub.playlist_names .. " saved", content_width), boxed and "YtPlayerFrame" or "YtPlayerAccent")
		if boxed then panel("N New   ·   r Rename   ·   Tab Switch pane", "YtPlayerKeyHint")
		else body("N New   ·   r Rename   ·   Tab Switch pane", "YtPlayerKeyHint"); divider() end
		if #hub.playlist_names == 0 then
			local write = boxed and panel or body
			write("Keep your favorites together.", "YtPlayerTitleText")
			write("Press N to create your first playlist.", "YtPlayerKeyHint")
			write("Press s on a search result to save a track.", "YtPlayerMuted")
			if boxed then
				while #lines < height - 1 do panel("") end
				body(layout.rule(content_width, nil, nil, true), "YtPlayerFrame")
			end
		else
			local split = width >= 80
			local left_width = split and math.floor((inner - 3) * 0.38) or inner
			local right_width = inner - left_width - 3
			local show_tracks = not split and hub.playlist_col == 2
			if split then split_panel("COLLECTION", "TRACKS · " .. name, left_width, right_width, "YtPlayerAccent", "YtPlayerAccent")
			elseif boxed then panel(show_tracks and "TRACKS · " .. name or "COLLECTION", "YtPlayerAccent")
			else body(show_tracks and "TRACKS · " .. name or "COLLECTION", "YtPlayerAccent") end
			local capacity = math.max(1, height - #lines - 1)
			local p_first, p_last = layout.viewport(#hub.playlist_names, hub.selected_pl_idx, capacity)
			local t_first, t_last = layout.viewport(#tracks, hub.selected_pl_track_idx, capacity)
			local count = split and math.max(p_last - p_first + 1, t_last - t_first + 1)
				or (show_tracks and math.max(1, t_last - t_first + 1) or p_last - p_first + 1)
			for offset = 1, boxed and capacity or math.min(count, capacity) do
				local p_index, t_index = p_first + offset - 1, t_first + offset - 1
				local p_name = p_index <= p_last and hub.playlist_names[p_index]
				local item = t_index <= t_last and tracks[t_index]
				local left = p_name and layout.track(p_index, p_name, tostring(#playlists[p_name]), left_width, selected_marker(p_index == hub.selected_pl_idx)) or ""
				local right = item and track(item, t_index, split and right_width or inner, t_index == hub.selected_pl_track_idx, duration(item), is_current(item)) or ""
				local left_group = p_index == hub.selected_pl_idx and (hub.playlist_col == 1 and "YtPlayerSelected" or "YtPlayerAccent") or "YtPlayerText"
				local right_group = t_index == hub.selected_pl_track_idx and hub.playlist_col == 2 and "YtPlayerSelected" or (item and is_current(item) and "YtPlayerPlaying" or "YtPlayerText")
				if #tracks == 0 and offset == 1 then right = "No tracks saved yet." end
				if split then split_panel(left, right, left_width, right_width, left_group, right_group)
				elseif boxed then panel(show_tracks and right or left, show_tracks and right_group or left_group)
				else body(show_tracks and right or left, show_tracks and right_group or left_group) end
				if p_name and (split or not show_tracks) then map_row(1, p_index) end
				if item and (split or show_tracks) then map_row(2, t_index) end
			end
			local first, last, total = p_first, p_last, #hub.playlist_names
			if hub.playlist_col == 2 then first, last, total = t_first, t_last, #tracks end
			local range = total > 0 and string.format("%d–%d of %d", first, last, total) or "EMPTY PLAYLIST"
			body(boxed and layout.rule(content_width, range, "Enter PLAY · a QUEUE", true) or range .. "   ·   Enter Play   ·   a Queue", boxed and "YtPlayerFrame" or "YtPlayerMuted")
		end
	elseif hub.active_tab == 5 then
		local history = require("yt-player.history").get()
		local boxed = height >= 12
		local inner = boxed and content_width - 4 or content_width
		body(boxed and layout.rule(content_width, "LISTENING HISTORY", #history .. " TRACKS") or layout.pair("RECENTLY PLAYED", #history .. " tracks", content_width), boxed and "YtPlayerFrame" or "YtPlayerAccent")
		if boxed then panel("Enter Replay   ·   a Queue   ·   s Save", "YtPlayerKeyHint")
		else body("Enter Replay   ·   a Queue   ·   s Save", "YtPlayerKeyHint"); divider() end
		if #history == 0 then
			local write = boxed and panel or body
			write("Rediscover your recent favorites here.", "YtPlayerMuted")
			write("Press / to find your first track.", "YtPlayerKeyHint")
			if boxed then
				while #lines < height - 1 do panel("") end
				body(layout.rule(content_width, nil, nil, true), "YtPlayerFrame")
			end
		else
			list(history, hub.selection[5], function(item, index, selected)
				local metadata = relative_time(item.timestamp)
				if width >= 64 then metadata = duration(item) .. "  " .. metadata end
				return track(item, index, inner, selected, metadata, is_current(item)), is_current(item) and "YtPlayerPlaying" or "YtPlayerText"
			end, boxed)
		end
	end
	if show_transport then
		while #lines < height do body("", "YtPlayerNormal") end
		divider()
		body(deck.transport(state, content_width), "YtPlayerTransport")
	end
	if legacy_footer then body("/ Search   ·   ? Help   ·   q Close", "YtPlayerKeyHint") end
	return lines, highlights, rows, indices
end

return M
