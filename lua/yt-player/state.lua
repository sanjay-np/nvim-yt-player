---@mod yt-player.state Centralized playback state
local M = {}

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
}

function M.setup(config)
  M.config = config
end

-- Throttle statusline redraws to max 5/sec
local last_redraw = 0

function M.update(data)
  -- Notify on track change
  if data.title and data.title ~= M.current.title then
    if M.config.notifications and M.config.notifications.notify_on_track_change then
      require("yt-player.notify").track_change(data.title, data.artist)
    end
  end

  -- Shallow merge (avoids tbl_deep_extend overhead on frequent time-pos updates)
  for k, v in pairs(data) do
    M.current[k] = v
  end

  local now = vim.loop.now()
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
