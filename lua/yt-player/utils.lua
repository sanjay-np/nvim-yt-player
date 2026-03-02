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

---Sanitize URL to prevent command injection
---@param url string
---@return string
function M.sanitize_url(url)
    if not url or type(url) ~= "string" then
        return ""
    end
    -- Remove newlines and control characters that could break IPC
    url = url:gsub("[%c\r\n]", "")
    -- Trim whitespace
    url = url:match("^%s*(.-)%s*$") or url
    return url
end

return M
