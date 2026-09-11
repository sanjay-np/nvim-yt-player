---@mod yt-player.notify Notification helpers
local M = {}

M.config = {}

function M.setup(config)
	M.config = config
end

---@param msg string
---@param level string|nil  "info"|"warn"|"error"
function M.notify(msg, level)
	if not M.config.enabled then
		return
	end
	vim.notify("YT Control: " .. msg, vim.log.levels[(level or "info"):upper()])
end

function M.info(msg)
	M.notify(msg, "info")
end

function M.warn(msg)
	M.notify(msg, "warn")
end

function M.error(msg)
	M.notify(msg, "error")
end

function M.track_change(title, artist)
	if not M.config.notify_on_track_change then
		return
	end
	local format = M.config.format or "▶ {title} - {artist}"
	local icon = M.config.icon_playing or "▶"
	local msg = format
		:gsub("{title}", function()
			return title or "Unknown"
		end)
		:gsub("{artist}", function()
			return artist or ""
		end)
		:gsub("{icon}", function()
			return icon
		end)
	M.info(msg)
end

return M
