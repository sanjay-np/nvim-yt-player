---@mod yt-player.notify Notification helpers
local M = {}

M.config = {}

function M.setup(config)
  M.config = config
end

---@param msg string
---@param level string|nil  "info"|"warn"|"error"
function M.notify(msg, level)
  if not M.config.enabled then return end
  vim.notify("YT Control: " .. msg, vim.log.levels[(level or "info"):upper()])
end

function M.info(msg) M.notify(msg, "info") end

function M.warn(msg) M.notify(msg, "warn") end

function M.error(msg) M.notify(msg, "error") end

function M.track_change(title, artist)
  if not M.config.notify_on_track_change then return end
  M.info(string.format("▶ Now playing: %s", title or "Unknown"))
end

return M
