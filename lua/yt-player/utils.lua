---@mod yt-player.utils Utility functions
local M = {}

---Format seconds to M:SS or H:MM:SS
---@param seconds number|nil
---@return string
function M.format_time(seconds)
    if not seconds or seconds == 0 or seconds ~= seconds then
        return "0:00"
    end
    seconds = math.floor(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%d:%02d", m, s)
end

return M
