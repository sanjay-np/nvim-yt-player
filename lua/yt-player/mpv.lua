local M = {}

local uv = vim.uv or vim.loop
local state_mod = require("yt-player.state")
local yt_utils = require("yt-player.utils")

M.config = {}
M.mpv_job_id = nil
M.ipc_pipe = nil
M.ipc_connected = false
M.ipc_socket_path = vim.fn.stdpath("cache") .. "/nvim-yt-player/ipc.sock"
M.client_registry_path = vim.fn.stdpath("cache") .. "/nvim-yt-player/clients.json"
M.is_external_client = false
M.current_url = ""

M.shutting_down = false

-- IPC buffer (mpv sends JSON strings separated by newlines)
local ipc_buffer = ""
local IPC_BUFFER_MAX = 1024 * 1024 -- 1MB limit to prevent unbounded growth

-- Pending commands to send once IPC is connected
local pending_commands = {}

-- Map request_id to property names so we can parse asynchronous get_property responses
local request_id_counter = 0
M.request_map = {}

local function read_registry()
	local data, _ = yt_utils.read_json_file(M.client_registry_path, {})
	return type(data) == "table" and data or {}
end

local function write_registry(data)
	yt_utils.atomic_write_json(M.client_registry_path, data)
end

local function cleanup_registry()
	local clients = read_registry()
	local active = {}
	for _, pid in ipairs(clients) do
		if uv.kill(pid, 0) == 0 then
			table.insert(active, pid)
		end
	end
	write_registry(active)
	return active
end

local function register_client()
	local active = cleanup_registry()
	local my_pid = vim.fn.getpid()
	local found = false
	for _, pid in ipairs(active) do
		if pid == my_pid then
			found = true
			break
		end
	end
	if not found then
		table.insert(active, my_pid)
		write_registry(active)
	end
end

local function unregister_client()
	local clients = read_registry()
	local active = {}
	local my_pid = vim.fn.getpid()
	for _, pid in ipairs(clients) do
		if pid ~= my_pid and uv.kill(pid, 0) == 0 then
			table.insert(active, pid)
		end
	end
	write_registry(active)
	return active
end

function M.setup(config)
	M.config = config
	M.shutting_down = false
	M.is_external_client = false

	-- Ensure cache directory exists
	local cache_dir = vim.fn.stdpath("cache") .. "/nvim-yt-player"
	if vim.fn.isdirectory(cache_dir) == 0 then
		vim.fn.mkdir(cache_dir, "p")
	end

	-- Auto-connect if another instance is running
	local active_clients = cleanup_registry()
	if #active_clients > 0 and vim.fn.filereadable(M.ipc_socket_path) == 1 then
		M.is_external_client = true
		register_client()
		M._connect_ipc_with_retry(0)
	end
end

local function ensure_sponsorblock_script()
	local script_path = vim.fn.stdpath("cache") .. "/yt_sponsorblock.lua"
	if vim.fn.filereadable(script_path) == 1 then
		return script_path
	end

	-- A minimal local Lua sponsorblock script for MPV
	local script_content = [[
local mp = require 'mp'
local utils = require 'mp.utils'
local msg = require 'mp.msg'

local segments = nil

mp.register_event("file-loaded", function()
    segments = nil
    local video_id = string.match(path, "v=([%w_%-]+)") or string.match(path, "youtu%.be/([%w_%-]+)") or string.match(path, "embed/([%w_%-]+)") or string.match(path, "shorts/([%w_%-]+)")
    if not video_id or #video_id ~= 11 then return end

    msg.info("Fetching SponsorBlock for " .. video_id)
    local url = "https://sponsor.ajay.app/api/skipSegments?videoID=" .. video_id .. "&categories=[\"sponsor\",\"intro\",\"outro\",\"interaction\",\"selfpromo\",\"music_offtopic\"]"
    
    mp.command_native_async({
        name = "subprocess",
        args = {"curl", "-s", url},
        capture_stdout = true,
        playback_only = false,
    }, function(success, res, err)
        if success and res.status == 0 and res.stdout and res.stdout ~= "" then
            local ok, parsed = pcall(utils.parse_json, res.stdout)
            if ok and type(parsed) == "table" then
                segments = parsed
                msg.info("SponsorBlock segments loaded for " .. video_id)
            end
        end
    end)
end)

mp.add_periodic_timer(1, function()
    if not segments then return end
    local pos = mp.get_property_number("time-pos")
    if not pos then return end

    for _, seg in ipairs(segments) do
        if seg.segment and pos >= seg.segment[1] and pos < seg.segment[2] then
            msg.info("Skipping sponsor segment: " .. seg.category)
            mp.set_property_number("time-pos", seg.segment[2])
            mp.osd_message("Skipped " .. seg.category, 3)
            return
        end
    end
end)
]]
	local f = io.open(script_path, "w")
	if f then
		f:write(script_content)
		f:close()
		return script_path
	end
	return nil
end

--- Start mpv with IPC enabled. If a url is provided, it is passed directly
--- on the command line so playback begins immediately without waiting for IPC.
---@param url string|nil  Optional URL to play immediately
function M.start(url)
	if M.shutting_down then
		return false
	end

	if M.is_running() then
		if url then
			M.load_url(url)
		end
		register_client()
		return true
	end

	-- Ensure yt-dlp and mpv exist
	if vim.fn.executable("mpv") == 0 then
		vim.notify("YT Control: mpv is not installed or not in PATH", vim.log.levels.ERROR)
		return false
	end
	if vim.fn.executable("yt-dlp") == 0 then
		vim.notify("YT Control: yt-dlp is not installed or not in PATH", vim.log.levels.ERROR)
		return false
	end

	-- Remove stale socket file only if no active clients are running
	local active_clients = cleanup_registry()
	if #active_clients == 0 then
		vim.fn.delete(M.ipc_socket_path)
	end

	local cmd = {
		"mpv",
		"--no-video",
		"--no-terminal",
		"--input-ipc-server=" .. M.ipc_socket_path,
	}

	-- Route stream resolution through yt-dlp player clients that YouTube
	-- does not 403-block when mpv fetches the resolved URL (see README).
	local client = M.config.youtube and M.config.youtube.player_client
	if type(client) == "string" and client ~= "" then
		table.insert(cmd, "--ytdl-raw-options-append=extractor-args=youtube:player_client=" .. client)
	end

	register_client()
	if M.config.sponsorblock then
		local script_path = ensure_sponsorblock_script()
		if script_path then
			table.insert(cmd, "--script=" .. script_path)
		end
	end

	-- If we have a URL, pass it directly so playback starts immediately
	-- Otherwise start in idle mode
	if url then
		table.insert(cmd, url)
	else
		table.insert(cmd, "--idle=yes")
	end

	local stderr_lines = {}

	M.mpv_job_id = vim.fn.jobstart(cmd, {
		detach = true,
		on_stderr = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						stderr_lines[#stderr_lines + 1] = line
					end
				end
			end
		end,
		on_exit = function(_, code)
			M.mpv_job_id = nil
			M.ipc_connected = false
			M._cleanup_ipc()
			state_mod.set_connected(false)
			if code ~= 0 and code ~= 143 and code ~= 15 and not M.shutting_down then
				vim.schedule(function()
					local err_msg = #stderr_lines > 0 and ("\n" .. table.concat(stderr_lines, "\n")) or ""
					vim.notify("YT Control: mpv exited (code " .. code .. ")" .. err_msg, vim.log.levels.WARN)
				end)
			end
		end,
	})

	if M.mpv_job_id <= 0 then
		vim.notify("YT Control: Failed to start mpv process", vim.log.levels.ERROR)
		M.mpv_job_id = nil
		return false
	end

	-- Wait briefly for socket to be created by mpv, then connect IPC
	M._connect_ipc_with_retry(0)

	return true
end

function M.is_running()
	return M.mpv_job_id ~= nil or M.is_external_client
end

--- Try to connect to IPC socket with retries (mpv needs a moment to create it)
---@param attempt number  Current retry attempt
function M._connect_ipc_with_retry(attempt)
	if M.shutting_down then
		return
	end
	if not M.is_running() then
		return
	end

	local max_attempts = 10
	local delay = 300 -- ms between retries

	vim.defer_fn(function()
		if M.shutting_down or not M.is_running() then
			return
		end

		M.ipc_pipe = uv.new_pipe(false)
		M.ipc_pipe:connect(M.ipc_socket_path, function(err)
			if err then
				-- Clean up failed pipe
				pcall(function()
					if M.ipc_pipe and not M.ipc_pipe:is_closing() then
						M.ipc_pipe:close()
					end
				end)
				M.ipc_pipe = nil

				if attempt < max_attempts then
					vim.schedule(function()
						M._connect_ipc_with_retry(attempt + 1)
					end)
				else
					vim.schedule(function()
						if M.shutting_down then
							return
						end
						if M.mpv_job_id ~= nil then
							local id = M.mpv_job_id
							M.mpv_job_id = nil
							pcall(vim.fn.jobstop, id)
						end
						M._cleanup_ipc()
						vim.fn.delete(M.ipc_socket_path)
					end)
				end
				return
			end

			-- Successfully connected!
			M.ipc_connected = true

			vim.schedule(function()
				if M.shutting_down then
					return
				end
				state_mod.set_connected(true)
				vim.notify("YT Control: Connected to mpv", vim.log.levels.INFO)

				-- Enable property observers
				M.send_command({ "observe_property", 1, "time-pos" })
				M.send_command({ "observe_property", 2, "pause" })
				M.send_command({ "observe_property", 3, "duration" })
				M.send_command({ "observe_property", 4, "volume" })
				M.send_command({ "observe_property", 5, "mute" })
				M.send_command({ "observe_property", 6, "speed" })
				M.send_command({ "observe_property", 7, "media-title" })
				M.send_command({ "observe_property", 8, "playlist" })
				M.send_command({ "observe_property", 9, "playlist-pos" })
				M.send_command({ "observe_property", 10, "playlist-count" })
				M.send_command({ "observe_property", 11, "loop-file" })
				M.send_command({ "observe_property", 12, "loop-playlist" })
				M.send_command({ "observe_property", 13, "metadata" })

				-- Fetch initial properties directly to populate the UI state immediately
				local function fetch_prop(prop_name)
					request_id_counter = request_id_counter + 1
					M.request_map[request_id_counter] = prop_name
					M.send_command({ "get_property", prop_name }, request_id_counter)
				end

				fetch_prop("pause")
				fetch_prop("media-title")
				fetch_prop("duration")
				fetch_prop("volume")
				fetch_prop("speed")
				fetch_prop("playlist")
				fetch_prop("playlist-pos")
				fetch_prop("loop-file")
				fetch_prop("loop-playlist")
				fetch_prop("metadata")

				-- Flush any pending commands that were queued before IPC was ready
				M._flush_pending()
			end)

			M.ipc_pipe:read_start(function(read_err, data)
				if M.shutting_down then
					return
				end
				if read_err then
					vim.schedule(function()
						M.ipc_connected = false
						M._cleanup_ipc()
					end)
					return
				end

				if data then
					ipc_buffer = ipc_buffer .. data
					M._process_ipc_buffer()
				else
					-- EOF
					vim.schedule(function()
						M.ipc_connected = false
						M._cleanup_ipc()
					end)
				end
			end)
		end)
	end, delay)
end

--- Flush pending commands that were queued before IPC was ready
function M._flush_pending()
	local cmds = pending_commands
	pending_commands = {}
	for _, cmd in ipairs(cmds) do
		if type(cmd) == "table" and cmd.command_list then
			M.send_command(cmd.command_list, cmd.request_id)
		else
			M.send_command(cmd)
		end
	end
end

function M._process_ipc_buffer()
	-- Safety: truncate buffer if it grows too large (prevents memory exhaustion)
	if #ipc_buffer > IPC_BUFFER_MAX then
		ipc_buffer = ipc_buffer:sub(-(IPC_BUFFER_MAX / 2))
	end

	local lines_batch = {}
	local pos = 1
	while true do
		local newline_pos = ipc_buffer:find("\n", pos)
		if not newline_pos then
			break
		end

		local line = ipc_buffer:sub(pos, newline_pos - 1)
		pos = newline_pos + 1

		if line ~= "" then
			lines_batch[#lines_batch + 1] = line
		end
	end

	if pos > 1 then
		ipc_buffer = ipc_buffer:sub(pos)
	end

	if #lines_batch > 0 then
		vim.schedule(function()
			if M.shutting_down then
				return
			end
			for _, line in ipairs(lines_batch) do
				if M.shutting_down then
					return
				end
				M._handle_ipc_message(line)
			end
		end)
	end
end

-- Property-to-state-key mapping table (avoids long if-else chain)
local prop_map = {
	["time-pos"] = { key = "position", default = 0 },
	["duration"] = { key = "duration", default = 0 },
	["volume"] = { key = "volume", default = 100 },
	["mute"] = { key = "muted", default = false },
	["speed"] = { key = "speed", default = 1 },
	["media-title"] = { key = "title", default = "Unknown" },
	["playlist"] = { key = "playlist", default = {} },
	["playlist-pos"] = { key = "playlist_pos", default = 0 },
	["playlist-count"] = { key = "playlist_count", default = 0 },
	["loop-file"] = { key = "loop_file", default = false },
	["loop-playlist"] = { key = "loop_playlist", default = false },
	["metadata"] = { key = "metadata", default = {} },
}

function M._handle_ipc_message(line)
	if M.shutting_down then
		return
	end

	local ok, msg = pcall(vim.json.decode, line)
	if not ok then
		return
	end

	-- Resolve property name and data from observers or get_property responses
	local prop_name, prop_data

	if msg.event == "property-change" then
		prop_name = msg.name
		prop_data = msg.data
	elseif msg.request_id then
		prop_name = M.request_map[msg.request_id]
		M.request_map[msg.request_id] = nil
		if msg.error == "success" and msg.data ~= nil then
			prop_data = msg.data
		end
	end

	if prop_name then
		-- Special case: "pause" is inverted to "playing"
		if prop_name == "pause" then
			state_mod.update({ playing = not prop_data })
			return
		end

		local mapping = prop_map[prop_name]
		if mapping then
			state_mod.update({ [mapping.key] = prop_data or mapping.default })
		end

		-- Backfill duration in history once resolved by yt-dlp
		if prop_name == "duration" and type(prop_data) == "number" and prop_data > 0 then
			local active_url = M.current_url or ""
			local current = state_mod.get_current()
			if current.playlist and current.playlist_pos then
				local active_item = current.playlist[current.playlist_pos + 1]
				if active_item and active_item.filename and active_item.filename ~= "" then
					active_url = active_item.filename
				end
			end
			if active_url ~= "" then
				pcall(function()
					require("yt-player.history").update_duration(active_url, prop_data)
				end)
			end
		end

		-- Record to play history when a new track starts
		if prop_name == "media-title" and prop_data and prop_data ~= "" then
			local current = state_mod.get_current()
			local active_url = M.current_url or ""
			if current.playlist and current.playlist_pos then
				local active_item = current.playlist[current.playlist_pos + 1]
				if active_item and active_item.filename and active_item.filename ~= "" then
					active_url = active_item.filename
					M.current_url = active_url
				end
			end

			pcall(function()
				require("yt-player.history").add({
					title = prop_data,
					url = active_url,
					duration = current.duration or 0,
				})
			end)
			-- Populate artist from artist_map (set by search/radio/queue)
			local artist_map = state_mod.current.artist_map or {}
			if active_url ~= "" and artist_map[active_url] then
				state_mod.update({ artist = artist_map[active_url] })
			end
		end

		-- Extract artist from mpv metadata if available (fallback)
		if prop_name == "metadata" and type(prop_data) == "table" then
			local meta_artist = prop_data.artist or prop_data.Artist or ""
			if meta_artist ~= "" then
				state_mod.update({ artist = meta_artist })
			end
		end
	elseif msg.event == "end-file" then
		if msg.reason ~= "stop" and msg.reason ~= "quit" then
			state_mod.update({ playing = false, position = 0, title = "Finished" })
		end
	end
end

--- Send a raw JSON IPC command to mpv
--- If IPC isn't connected yet but mpv is running, queue the command.
---@param command_list table E.g. {"set_property", "pause", true}
---@param request_id number|nil
function M.send_command(command_list, request_id)
	if M.shutting_down then
		return false
	end

	-- If IPC isn't ready yet but mpv is running, queue the command
	if not M.ipc_connected or not M.ipc_pipe then
		if M.is_running() then
			table.insert(pending_commands, { command_list = command_list, request_id = request_id })
			return true -- queued
		end
		return false
	end

	if M.ipc_pipe:is_closing() then
		return false
	end

	local payload = { command = command_list }
	if request_id then
		payload.request_id = request_id
	end

	local ok, json = pcall(vim.json.encode, payload)
	if not ok then
		return false
	end

	pcall(function()
		M.ipc_pipe:write(json .. "\n")
	end)

	return true
end

--- High-level control function: Load URL
function M.load_url(url)
	-- Sanitize URL to prevent command injection
	url = yt_utils.sanitize_url(url)
	if url == "" then
		vim.notify("YT Control: Invalid URL", vim.log.levels.ERROR)
		return false
	end

	-- Track URL for history logging
	M.current_url = url

	if not M.is_running() then
		M.start(url)
	else
		M.send_command({ "loadfile", url, "replace" })
	end

	state_mod.update({
		title = "Loading...",
		playing = false,
		position = 0,
		duration = 0,
		artist = "",
	})
end

function M._cleanup_ipc()
	if M.ipc_pipe then
		pcall(function()
			M.ipc_pipe:read_stop()
			if not M.ipc_pipe:is_closing() then
				M.ipc_pipe:close()
			end
		end)
		M.ipc_pipe = nil
	end
	M.ipc_connected = false
	M.is_external_client = false
	ipc_buffer = ""
end

function M.shutdown()
	M.shutting_down = true

	local remaining = unregister_client()
	if #remaining == 0 then
		-- Try sending quit directly to the pipe (bypassing send_command which blocks on shutting_down)
		if M.ipc_connected and M.ipc_pipe and not M.ipc_pipe:is_closing() then
			pcall(function()
				M.ipc_pipe:write('{"command":["quit"]}\n')
			end)
		end
		M._cleanup_ipc()

		if M.mpv_job_id ~= nil then
			local id = M.mpv_job_id
			M.mpv_job_id = nil
			pcall(function()
				vim.fn.jobstop(id)
			end)
		end

		-- Clean up socket file
		pcall(function()
			os.remove(M.ipc_socket_path)
		end)
	else
		M._cleanup_ipc()
	end
end

return M
