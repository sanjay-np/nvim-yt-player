---@mod yt-player.playlists Persistent local playlists
local M = {}

local utils = require("yt-player.utils")
local state_mod = require("yt-player.state")

local function get_path()
	return vim.fn.stdpath("data") .. "/yt-player-playlists.json"
end

--- Read all playlists
---@return table { [playlist_name] = { {title, url, duration, added_at}, ... } }
function M.get_all()
	return utils.read_json_store(get_path(), "playlists")
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

return M
