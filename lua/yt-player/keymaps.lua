---@mod yt-player.keymaps Global keymaps
local M = {}

function M.setup(config)
  if not config.enabled then return end

  local p = config.prefix
  local map = function(key, cmd, desc)
    vim.keymap.set("n", p .. key, "<cmd>YT " .. cmd .. "<cr>", { desc = "YT: " .. desc })
  end

  map(config.play, "play", "Play")
  map(config.pause, "pause", "Pause")
  map(config.toggle, "toggle", "Toggle")
  map(config.next, "next", "Next")
  map(config.prev, "prev", "Previous")
  map(config.mute, "mute", "Mute")
  map(config.volume_up, "vol_up", "Volume +5")
  map(config.volume_down, "vol_down", "Volume -5")
  map(config.seek_forward, "seek_rel 10", "Seek +10s")
  map(config.seek_backward, "seek_rel -10", "Seek -10s")
  map(config.speed_up, "speed_up", "Speed Up")
  map(config.speed_down, "speed_down", "Speed Down")
  map(config.info, "info", "Player Window")
end

return M
