---@mod yt-player.session Persistent session save and auto-resume
local M = {}

local utils = require("yt-player.utils")

local function session_path()
	return vim.fn.stdpath("data") .. "/yt-player-session.json"
end

--- Save current playback session to disk
function M.save()
	-- Only save if mpv is running and there is an active playlist
	local ok_mpv, mpv = pcall(require, "yt-player.mpv")
	if not ok_mpv or not mpv.is_running() then
		return
	end

	local ok_state, state_mod = pcall(require, "yt-player.state")
	if not ok_state then
		return
	end

	local state = state_mod.get_current()
	if not state.playlist or #state.playlist == 0 then
		return
	end

	local data = {
		playlist = state.playlist,
		playlist_pos = state.playlist_pos or 0,
		position = state.position or 0,
		volume = state.volume or 100,
		speed = state.speed or 1,
		loop_file = state.loop_file or "no",
		loop_playlist = state.loop_playlist or "no",
		playlist_meta = state.playlist_meta or {},
		artist_map = state.artist_map or {},
	}

	utils.atomic_write_json(session_path(), data)
end

--- Restore playback session from disk
function M.restore()
	local data, is_corrupt = utils.read_json_file(session_path(), nil)
	if is_corrupt or not data or type(data) ~= "table" or not data.playlist or #data.playlist == 0 then
		vim.notify("YT Control: No saved session found", vim.log.levels.WARN)
		return
	end

	local mpv = require("yt-player.mpv")
	local state_mod = require("yt-player.state")

	vim.notify("YT Control: Resuming saved session...", vim.log.levels.INFO)

	-- 1. Restore playlist metadata so UI is immediately accurate
	state_mod.current.playlist_meta = state_mod.current.playlist_meta or {}
	state_mod.current.artist_map = state_mod.current.artist_map or {}
	if data.playlist_meta then
		for k, v in pairs(data.playlist_meta) do
			state_mod.current.playlist_meta[k] = v
		end
	end
	if data.artist_map then
		for k, v in pairs(data.artist_map) do
			state_mod.current.artist_map[k] = v
		end
	end



	-- 2. Start mpv in idle mode if it is not already running
	if not mpv.is_running() then
		mpv.start(nil)
	end

	-- 4. Load tracks and configure properties sequentially
	local function apply_session()
		-- Load all files into mpv playlist
		for i, item in ipairs(data.playlist) do
			local mode = (i == 1) and "replace" or "append"
			mpv.send_command({ "loadfile", item.filename, mode })
		end

		-- Restore playback properties after a short delay
		vim.defer_fn(function()
			mpv.send_command({ "set_property", "playlist-pos", data.playlist_pos or 0 })
			mpv.send_command({ "set_property", "volume", data.volume or 100 })
			mpv.send_command({ "set_property", "speed", data.speed or 1 })
			mpv.send_command({ "set_property", "loop-file", data.loop_file or "no" })
			mpv.send_command({ "set_property", "loop-playlist", data.loop_playlist or "no" })

			-- Seek to position (give file parsing a slight buffer time)
			if data.position and data.position > 0 then
				vim.defer_fn(function()
					mpv.send_command({ "seek", data.position, "absolute" })
				end, 1000)
			end
		end, 500)
	end

	apply_session()
end

return M
