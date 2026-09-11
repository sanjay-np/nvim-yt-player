---@mod yt-player.radio YouTube Autoplay Radio Engine
local M = {}

local uv = vim.uv or vim.loop

M.is_fetching = false
M.active_handle = nil
M.failed_video_ids = {}
M.cooldown_seconds = 60

--- Cancel any active recommendation fetch job
function M.cancel()
	if M.active_handle then
		pcall(function()
			if not M.active_handle:is_closing() then
				M.active_handle:kill(15) -- SIGTERM
				M.active_handle:close()
			end
		end)
		M.active_handle = nil
	end
	M.failed_video_ids = {}
	local state_mod = require("yt-player.state")
	local state = state_mod.get_current()
	state.radio_fetching = false
end

--- Toggle radio mode
function M.toggle()
	local state_mod = require("yt-player.state")
	local state = state_mod.get_current()
	state.radio_enabled = not state.radio_enabled

	if state.radio_enabled then
		M.failed_video_ids = {}
		vim.notify("YT Control: 📻 Autoplay Radio: ON", vim.log.levels.INFO)
		M.check_and_trigger()
	else
		M.cancel()
		vim.notify("YT Control: 📻 Autoplay Radio: OFF", vim.log.levels.INFO)
	end

	pcall(vim.cmd, "redrawstatus!")
end

--- Extract YouTube Video ID from any standard or shortened URL
---@param url string|nil
---@return string|nil
function M.extract_video_id(url)
	if not url or type(url) ~= "string" then
		return nil
	end
	local id = string.match(url, "v=([%w_%-]+)")
		or string.match(url, "youtu%.be/([%w_%-]+)")
		or string.match(url, "embed/([%w_%-]+)")
		or string.match(url, "shorts/([%w_%-]+)")
	if id and #id == 11 then
		return id
	end
	return nil
end

--- Asynchronously fetch related tracks for a video via yt-dlp Mix list
---@param video_id string
---@param limit number
---@param callback fun(tracks: table[], err: string|nil)
---@return uv_process_t|nil handle
function M.get_related_tracks(video_id, limit, callback)
	if vim.fn.executable("yt-dlp") == 0 then
		callback({}, "yt-dlp is not installed or not in PATH")
		return nil
	end

	limit = limit or 5
	local mix_url = string.format("https://www.youtube.com/watch?v=%s&list=RD%s", video_id, video_id)

	local args = {
		"yt-dlp",
		"--flat-playlist",
		"--dump-json",
		"--no-warnings",
		"--no-download",
		"--playlist-start",
		"2", -- Start from index 2 to skip currently playing video
		"--playlist-end",
		tostring(limit + 1),
		mix_url,
	}

	local stdout = uv.new_pipe(false)
	local results = {}

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
			if code ~= 0 then
				callback({}, "yt-dlp failed to fetch Mix playlist")
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
		callback({}, "Failed to spawn yt-dlp")
		return nil
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

	return handle
end

--- Check playback status and trigger recommendation fetch if queue is ending
function M.check_and_trigger()
	local state_mod = require("yt-player.state")
	local state = state_mod.get_current()

	-- Guard clauses
	if not state.radio_enabled then
		return
	end
	if state.radio_fetching then
		return
	end

	local mpv = require("yt-player.mpv")
	if not mpv.is_running() or not mpv.ipc_connected then
		return
	end

	local plist = state.playlist or {}
	if #plist == 0 then
		return
	end

	-- Check if we are on the last track in the playlist (0-indexed pos)
	local is_last_track = (state.playlist_pos or 0) >= #plist - 1
	if not is_last_track then
		return
	end

	local current_track = plist[(state.playlist_pos or 0) + 1]
	if not current_track then
		return
	end

	local filename = current_track.filename or ""
	local video_id = M.extract_video_id(filename)
	if not video_id then
		-- Graceful skip: not a YouTube URL
		return
	end

	local now = os.time()
	local last_fail = M.failed_video_ids[video_id] or 0
	if (now - last_fail) < (M.cooldown_seconds or 60) then
		return
	end

	state.radio_fetching = true

	local limit = 5
	local config = require("yt-player").config
	if config and config.radio and config.radio.limit then
		limit = config.radio.limit
	end

	vim.notify("YT Radio: Fetching recommendations based on active track...", vim.log.levels.INFO)

	M.active_handle = M.get_related_tracks(video_id, limit, function(tracks, err)
		M.active_handle = nil
		state.radio_fetching = false

		-- Guard clause: verify radio mode is still enabled before queuing
		if not state.radio_enabled then
			return
		end

		if err then
			M.failed_video_ids[video_id] = os.time()
			vim.notify("YT Radio: Error - " .. err, vim.log.levels.WARN)
			return
		end

		if #tracks == 0 then
			M.failed_video_ids[video_id] = os.time()
			return
		end

		-- Load history to deduplicate
		local history = {}
		local ok_hist, history_mod = pcall(require, "yt-player.history")
		if ok_hist then
			history = history_mod.get() or {}
		end

		-- Set up set of existing URLs in playlist to filter out duplicates
		local existing = {}
		for _, item in ipairs(plist) do
			if item.filename then
				existing[item.filename] = true
			end
		end
		for _, item in ipairs(history) do
			if item.url then
				existing[item.url] = true
			end
		end

		local added_count = 0
		for _, track in ipairs(tracks) do
			if track.url ~= "" and not existing[track.url] then
				-- Append to metadata store so the UI is immediately populated
				state.playlist_meta = state.playlist_meta or {}
				state.artist_map = state.artist_map or {}
				state.playlist_meta[track.url] = track.title or "Unknown"
				if track.channel and track.channel ~= "" then
					state.artist_map[track.url] = track.channel
				end

				-- Append to mpv queue
				mpv.send_command({ "loadfile", track.url, "append" })
				added_count = added_count + 1
			end
		end

		if added_count > 0 then
			M.failed_video_ids[video_id] = nil
			vim.notify(string.format("YT Radio: Queued %d recommended track(s)", added_count), vim.log.levels.INFO)
		else
			-- No new unique tracks were found to add; record failure cooldown to prevent loop
			M.failed_video_ids[video_id] = os.time()
		end
	end)
end

return M
