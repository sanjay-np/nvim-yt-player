---@mod yt-player.status Statusline integration
local M = {}

M.config = {}

local state_mod = require("yt-player.state")
local utils = require("yt-player.utils")

-- Cache
local cached_line = nil
local cached_hash = nil

function M.setup(config)
  M.config = config
  cached_line = nil
  cached_hash = nil
end

local function state_hash(s)
  return string.format("%s|%s|%s|%s|%d|%d|%d|%.2f",
    tostring(s.connected), tostring(s.playing),
    s.title or "", s.artist or "",
    math.floor(s.position or 0), math.floor(s.duration or 0),
    math.floor(s.volume or 100), s.speed or 1)
end

local function progress_bar(position, duration, width)
  width = width or 10
  if not duration or duration <= 0 then return string.rep("░", width) end
  local filled = math.floor(math.min((position or 0) / duration, 1) * width)
  return string.rep("▓", filled) .. string.rep("░", width - filled)
end

function M.get_statusline()
  if not M.config.enabled then return "" end

  local state = state_mod.get_current()
  if not state.connected then return "" end
  if not state.title then return "YT: Waiting..." end

  local h = state_hash(state)
  if cached_line and cached_hash == h then return cached_line end

  local icon = state.playing and M.config.icon_playing or M.config.icon_paused
  local title = state.title or "Unknown"
  if #title > M.config.truncate_title then
    title = title:sub(1, M.config.truncate_title - 3) .. "..."
  end

  local speed = (state.speed and state.speed ~= 1) and string.format("%.2gx", state.speed) or ""

  local result = M.config.format
      :gsub("{icon}", icon)
      :gsub("{title}", title)
      :gsub("{artist}", state.artist or "")
      :gsub("{album}", state.album or "")
      :gsub("{position}", utils.format_time(state.position))
      :gsub("{duration}", utils.format_time(state.duration))
      :gsub("{volume}", tostring(math.floor(state.volume or 100)))
      :gsub("{progress}", progress_bar(state.position, state.duration, M.config.progress_width))
      :gsub("{speed}", speed)

  cached_line = result
  cached_hash = h
  return result
end

return M
