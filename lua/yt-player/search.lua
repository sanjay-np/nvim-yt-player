---@mod yt-player.search YouTube search and playlist import via yt-dlp
local M = {}

local uv = vim.uv or vim.loop
local state_mod = require("yt-player.state")

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
					-- "append-play" starts an idle mpv (freshly started, or its
					-- queue ended); plain "append" would queue tracks silently.
					mpv.send_command({ "loadfile", item.url, "append-play" })
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
						mpv.send_command({ "loadfile", item.url, "append-play" })
					end
					buffer_items = {}
				end)
			end
		end
	end)
end

return M
