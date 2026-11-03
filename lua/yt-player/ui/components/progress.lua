---@mod yt-player.ui.components.progress Smooth progress bars and volume gauges
local M = {}

local theme = require("yt-player.ui.theme")

--- Build a progress bar string
---@param position number|nil Current position in seconds
---@param duration number|nil Total duration in seconds
---@param width number Width in columns
---@param style string|nil "slider" | "blocks" | "smooth"
---@return string bar, number filled_ratio
function M.bar(position, duration, width, style)
	width = math.max(1, math.floor(width or 20))
	style = style or "slider"

	if not duration or duration <= 0 then
		if style == "blocks" or style == "smooth" then
			return string.rep("░", width), 0
		else
			return string.rep("─", width), 0
		end
	end

	local ratio = math.max(0, math.min((position or 0) / duration, 1))

	if style == "blocks" then
		local filled = math.floor(ratio * width)
		return string.rep("█", filled) .. string.rep("░", width - filled), ratio
	elseif style == "smooth" then
		local smooth_chars = { " ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" }
		local total_units = math.floor(ratio * width * 8)
		local full_chars = math.floor(total_units / 8)
		local rem_units = total_units % 8

		local result = string.rep("█", full_chars)
		if full_chars < width then
			if rem_units > 0 then
				result = result .. smooth_chars[rem_units + 1]
				result = result .. string.rep("░", width - full_chars - 1)
			else
				result = result .. string.rep("░", width - full_chars)
			end
		end
		return result, ratio
	else -- "slider"
		local filled = math.floor(ratio * width)
		if filled <= 0 then
			return "○" .. string.rep("─", width - 1), ratio
		elseif filled >= width then
			return string.rep("━", width - 1) .. "●", ratio
		else
			return string.rep("━", filled) .. "●" .. string.rep("─", width - filled - 1), ratio
		end
	end
end

--- Build a volume gauge string
---@param volume number|nil Volume (0-100)
---@param width number|nil Gauge width in columns (default 10)
---@param muted boolean|nil
---@return string icon, string gauge, number vol_val
function M.volume_gauge(volume, width, muted)
	width = width or 10
	local vol = math.floor(volume or 100)
	local icon

	if muted or vol == 0 then
		icon = theme.icon("volume_mute")
	elseif vol < 33 then
		icon = theme.icon("volume_low")
	elseif vol < 66 then
		icon = theme.icon("volume_med")
	else
		icon = theme.icon("volume_high")
	end

	local filled = math.max(0, math.min(width, math.floor((vol / 100) * width)))
	local gauge = string.rep("▰", filled) .. string.rep("▱", width - filled)

	return icon, gauge, vol
end

return M
