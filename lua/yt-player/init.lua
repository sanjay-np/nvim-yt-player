---@mod yt-player Plugin entry point
local M = {}

M.config = {
  statusline = {
    enabled = true,
    format = "{icon} {title} - {artist} [{position}/{duration}]",
    icon_playing = "▶",
    icon_paused = "⏸",
    truncate_title = 30,
    progress_width = 10,
  },

  search = {
    limit = 10,
  },

  notifications = {
    enabled = true,
    notify_on_track_change = true,
  },

  player = {
    queue_display_limit = 5, -- Minimum/Maximum number of upcoming tracks to show in the player UI
  },

  keymaps = {
    enabled = false,
    prefix = "<leader>y",
    play = "p",
    pause = "s",
    toggle = "t",
    next = "n",
    prev = "b",
    mute = "m",
    volume_up = "+",
    volume_down = "-",
    seek_forward = "f",
    seek_backward = "r",
    speed_up = ">",
    speed_down = "<",
    info = "i",
  },

  sponsorblock = false, -- Set to true to enable auto-skipping
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  M.mpv = require("yt-player.mpv")
  M.state = require("yt-player.state")
  M.status = require("yt-player.status")

  M.mpv.setup(M.config)
  M.state.setup(M.config)
  require("yt-player.notify").setup(M.config.notifications)
  M.status.setup(M.config.statusline)
  require("yt-player.commands").setup(M.config)

  if M.config.keymaps.enabled then
    require("yt-player.keymaps").setup(M.config.keymaps)
  end

  vim.g.yt_control_loaded = true

  vim.api.nvim_create_autocmd("VimLeave", {
    group = vim.api.nvim_create_augroup("YTControlCleanup", { clear = true }),
    callback = function()
      pcall(function() M.mpv.shutdown() end)
    end,
  })
end

--- Send a raw mpv IPC command table
function M.command(cmd_table)
  return M.mpv.send_command(cmd_table)
end

--- Load a URL or search into mpv
function M.load(url)
  return M.mpv.load_url(url)
end

function M.statusline()
  return M.status.get_statusline()
end

function M.get_state()
  return M.state.get_current()
end

function M.is_connected()
  return M.mpv.is_running() and M.mpv.ipc_connected
end

return M
