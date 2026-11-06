---@mod yt-player.state Centralized playback state
local M = {}

local uv = vim.uv or vim.loop

M.config = {}

M.current = {
	title = nil,
	artist = nil,
	album = nil,
	duration = 0,
	position = 0,
	playing = false,
	volume = 100,
	muted = false,
	speed = 1,
	connected = false,
	playlist = {},
	playlist_pos = 0,
	playlist_count = 0,
	playlist_meta = {},
	artist_map = {},
	radio_enabled = true,
	radio_fetching = false,
}

function M.setup(config)
	M.config = config
	if M.config.radio and M.config.radio.enabled ~= nil then
		M.current.radio_enabled = M.config.radio.enabled ~= false
	end
end

-- Throttle statusline redraws to max 5/sec
local last_redraw = 0

-- Titles shown while a track loads or after it ends, plus the raw URL/filename
-- mpv reports before yt-dlp resolves the real title. None is a track change.
local PLACEHOLDER_TITLES = { ["Loading..."] = true, ["Finished"] = true, ["Unknown"] = true }

local function is_track_title(title)
	return type(title) == "string"
		and title ~= ""
		and not PLACEHOLDER_TITLES[title]
		and not title:match("^https?://")
		and not title:match("^ytdl://")
		and not title:match("^watch%?v=")
end

function M.update(data)
	-- Notify on track change
	if is_track_title(data.title) and data.title ~= M.current.title then
		if M.config.notifications and M.config.notifications.notify_on_track_change then
			require("yt-player.notify").track_change(data.title, data.artist)
		end
	end

	-- Shallow merge (avoids tbl_deep_extend overhead on frequent time-pos updates)
	for k, v in pairs(data) do
		M.current[k] = v
	end

	-- Trigger Radio check on track/playlist updates
	if data.playlist_pos or data.playlist then
		pcall(function()
			require("yt-player.radio").check_and_trigger()
		end)
	end

	local now = uv.now()
	if now - last_redraw > 200 then
		last_redraw = now
		pcall(vim.cmd, "redrawstatus!")
	end
end

function M.set_connected(connected)
	M.current.connected = connected
	pcall(vim.cmd, "redrawstatus!")
end

function M.get_current()
	return M.current
end

return M
