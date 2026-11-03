---@mod yt-player.ui.layout Display-column-aware layout primitives
local M = {}
local utils = require("yt-player.utils")

function M.fit(text, width)
	width = math.max(0, width)
	return utils.pad_right(utils.safe_truncate(text, width), width)
end

--- Keep metadata inside its own column instead of overlaying the title.
function M.pair(left, right, width)
	width = math.max(0, width)
	if not right or right == "" or width < 18 then
		return M.fit(left, width)
	end
	right = utils.safe_truncate(right, math.floor(width * 0.45))
	local right_width = vim.fn.strdisplaywidth(right)
	return M.fit(left, math.max(0, width - right_width - 2)) .. "  " .. right
end

function M.track(index, title, metadata, width, marker)
	local prefix = string.format("%s %2d  ", marker or " ", index)
	return M.pair(prefix .. title, metadata, width)
end

--- Labeled rules and inset rows for terminal panels.
function M.rule(width, title, right, bottom)
	local left_corner, right_corner = bottom and "╰" or "╭", bottom and "╯" or "╮"
	local inside = math.max(0, width - 2)
	local label = title and title ~= "" and "─ " .. title .. " " or ""
	label = utils.safe_truncate(label, inside)
	local suffix = right and right ~= "" and " " .. right .. " ─" or ""
	suffix = utils.safe_truncate(suffix, math.max(0, inside - vim.fn.strdisplaywidth(label) - 1))
	local fill = math.max(0, inside - vim.fn.strdisplaywidth(label .. suffix))
	return left_corner .. label .. string.rep("─", fill) .. suffix .. right_corner
end

function M.inset(text, width)
	return "│ " .. M.fit(text, math.max(0, width - 4)) .. " │"
end

--- Fixed table columns keep artist and time aligned across every row.
function M.track_columns(index, title, artist, duration, width, marker)
	local prefix = index and string.format("%s %03d  ", marker or " ", index) or "  #    "
	local time_width = math.min(7, math.max(0, width - 16))
	local artist_width = width >= 66 and math.min(26, math.floor(width * 0.25)) or 0
	local title_width = math.max(1, width - vim.fn.strdisplaywidth(prefix) - time_width - (artist_width > 0 and artist_width + 2 or 0))
	local text = prefix .. M.fit(title, title_width)
	if artist_width > 0 then text = text .. M.fit(artist, artist_width) .. "  " end
	local time = utils.safe_truncate(duration or "", time_width)
	return M.fit(text .. string.rep(" ", math.max(0, time_width - vim.fn.strdisplaywidth(time))) .. time, width)
end

--- A bounded viewport keeps navigation and fixed search controls visible.
function M.viewport(count, selected, capacity)
	capacity = math.max(1, capacity)
	selected = math.max(1, math.min(selected, math.max(1, count)))
	local first = math.max(1, math.min(selected - math.floor(capacity / 2), count - capacity + 1))
	return first, math.min(count, first + capacity - 1), selected
end

--- Wrap full track titles in the details pane, including wide Unicode text.
function M.wrap(text, width, limit)
	local lines = {}
	text = (text or ""):gsub("[%c]", " ")
	width = math.max(1, width)
	while text ~= "" and #lines < (limit or 3) do
		if vim.fn.strdisplaywidth(text) <= width then
			table.insert(lines, text)
			break
		end
		if #lines == (limit or 3) - 1 then
			table.insert(lines, utils.safe_truncate(text, width))
			break
		end
		local count = 1
		while vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, count + 1)) <= width do
			count = count + 1
		end
		local segment = vim.fn.strcharpart(text, 0, count)
		local boundary = segment:match("^(.*)%s+%S*$")
		if boundary and vim.fn.strdisplaywidth(boundary) >= math.floor(width / 2) then
			segment = boundary
			count = vim.fn.strchars(segment)
		end
		table.insert(lines, utils.safe_truncate(segment, width))
		text = vim.fn.strcharpart(text, count):gsub("^%s+", "")
	end
	return lines
end

return M
