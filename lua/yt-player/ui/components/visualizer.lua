---@mod yt-player.ui.components.visualizer Animated audio visualizers and TUI vinyl art
local M = {}

local theme = require("yt-player.ui.theme")

local wave_frames = {
	"▃ ▅ ▇ █ ▇ ▅ ▃   ▃ ▅ ▇ █ ▇ ▅ ▃   ▃ ▅ ▇ █ ▇ ▅ ▃",
	"▅ ▇ █ ▆ █ ▇ ▅ ▂ ▅ ▇ █ ▆ █ ▇ ▅ ▂ ▅ ▇ █ ▆ █ ▇ ▅",
	"▇ █ ▆ ▄ ▆ █ ▇ ▃ ▇ █ ▆ ▄ ▆ █ ▇ ▃ ▇ █ ▆ ▄ ▆ █ ▇",
	"█ ▆ ▄ ▂ ▄ ▆ █ ▅ █ ▆ ▄ ▂ ▄ ▆ █ ▅ █ ▆ ▄ ▂ ▄ ▆ █",
	"▆ ▄ ▂   ▂ ▄ ▆ ▇ ▆ ▄ ▂   ▂ ▄ ▆ ▇ ▆ ▄ ▂   ▂ ▄ ▆",
	"▄ ▂   ▂   ▂ ▄ ▆ ▄ ▂   ▂   ▂ ▄ ▆ ▄ ▂   ▂   ▂ ▄",
	"▂   ▂ ▃ ▂   ▂ ▄ ▂   ▂ ▃ ▂   ▂ ▄ ▂   ▂ ▃ ▂   ▂",
	"  ▂ ▃ ▅ ▃ ▂   ▂   ▂ ▃ ▅ ▃ ▂   ▂   ▂ ▃ ▅ ▃ ▂  ",
	"▂ ▃ ▅ ▇ ▅ ▃ ▂   ▂ ▃ ▅ ▇ ▅ ▃ ▂   ▂ ▃ ▅ ▇ ▅ ▃ ▂",
}

local spectrum_frames = {
	{ "   █   █         █   █   ", " █ █ █ █ █     █ █ █ █ █ ", " ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ " },
	{ "     █   █     █   █     ", " █ █ █ █ █ █ █ █ █ █ █ █ ", " ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ " },
	{ " █         █ █         █ ", " █ █ █   █ █ █ █   █ █ █ ", " ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ " },
	{ "   █ █         █ █   █   ", " █ █ █ █     █ █ █ █ █ █ ", " ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ ▄ " },
}

local bar_frames = {
	" ▂ ▃ ▅ ▇ █ ▇ ▅ ▃ ▂  ▂ ▃ ▅ ▇ █ ▇ ▅ ▃ ▂ ",
	"▂ ▃ ▅ ▇ █ ▆ ▅ ▃ ▂  ▂ ▃ ▅ ▇ █ ▆ ▅ ▃ ▂  ",
	"▃ ▅ ▇ █ ▆ ▅ ▄ ▂   ▂ ▃ ▅ ▇ █ ▆ ▅ ▄ ▂   ",
	"▅ ▇ █ ▆ ▅ ▄ ▂   ▂ ▃ ▅ ▇ █ ▆ ▅ ▄ ▂   ▂ ",
	"▇ █ ▆ ▅ ▄ ▂   ▂ ▃ ▅ ▇ █ ▆ ▅ ▄ ▂   ▂ ▃ ",
	"█ ▆ ▅ ▄ ▂   ▂ ▃ ▅ ▇ █ ▆ ▅ ▄ ▂   ▂ ▃ ▅ ",
	"▆ ▅ ▄ ▂   ▂ ▃ ▅ ▇ █ ▆ ▅ ▄ ▂   ▂ ▃ ▅ ▇ ",
	"▅ ▄ ▂   ▂ ▃ ▅ ▇ █ ▆ ▅ ▄ ▂   ▂ ▃ ▅ ▇ █ ",
}

local dot_frames = {
	"· : ⁚ ⁝ ⁚ : ·   · : ⁚ ⁝ ⁚ : ·",
	": ⁚ ⁝ ⁚ : · :   : ⁚ ⁝ ⁚ : · :",
	"⁚ ⁝ ⁚ : · : ⁚   ⁚ ⁝ ⁚ : · : ⁚",
	"⁝ ⁚ : · : ⁚ ⁝   ⁝ ⁚ : · : ⁚ ⁝",
}

local vinyl_notes = {
	{ top = "♫", right = " ", bottom = " ", left = "♪" },
	{ top = " ", right = "♬", bottom = " ", left = "♩" },
	{ top = "♪", right = "♫", bottom = " ", left = " " },
	{ top = " ", right = " ", bottom = "♩", left = "♬" },
	{ top = "♩", right = " ", bottom = "♫", left = " " },
	{ top = " ", right = "♬", bottom = " ", left = "♪" },
	{ top = "♬", right = "♩", bottom = " ", left = " " },
	{ top = " ", right = " ", bottom = "♪", left = "♫" },
}

local current_idx = 1
local vinyl_idx = 1
M.current_style = "wave"
local STYLES = { "wave", "bars", "dots", "none" }

--- Cycle to next visualizer style
---@return string
function M.cycle_style()
	local found = 1
	for i, s in ipairs(STYLES) do
		if s == M.current_style then
			found = i
			break
		end
	end
	M.current_style = STYLES[(found % #STYLES) + 1]
	return M.current_style
end

--- Get the next animated visualizer frame
---@param style string|nil "wave" | "bars" | "dots" | "none"
---@param is_playing boolean|nil
---@return string
function M.next_frame(style, is_playing)
	style = style or M.current_style or "wave"
	if style == "none" then
		return ""
	end

	local frames = wave_frames
	if style == "bars" then
		frames = bar_frames
	elseif style == "dots" then
		frames = dot_frames
	end

	if not is_playing then
		return frames[1]
	end

	current_idx = (current_idx % #frames) + 1
	return frames[current_idx]
end

--- Decorative spectrum animation; it does not claim to measure audio levels.
function M.spectrum(width, height, is_playing, style)
	width, height = math.max(1, width), math.max(1, height)
	if is_playing and style ~= "none" then current_idx = current_idx + 1 end
	local count = math.max(1, math.floor((width + 1) / 2))
	local levels = {}
	for index = 1, count do
		local motion = math.sin(index * 0.83 + current_idx * 0.65) + math.sin(index * 0.37 - current_idx * 0.31)
		if style == "bars" then motion = math.abs(math.sin(index * 1.71 + current_idx * 0.48)) * 4 - 2 end
		levels[index] = is_playing and style ~= "none" and math.floor((motion + 2) * height * 2) or 1
	end
	local blocks = { " ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }
	local rows = {}
	for row = 1, height do
		local parts = {}
		for index = 1, count do
			local amount = math.max(0, math.min(8, levels[index] - (height - row) * 8))
			parts[index] = style == "none" and "" or (style == "dots" and (amount > 0 and (amount == 8 and "·" or "●") or " ") or blocks[amount + 1])
		end
		rows[row] = table.concat(parts, " ")
	end
	return rows
end

--- Fixed-width record artwork with a rotating label and no font dependency.
function M.record(is_playing, compact)
	if is_playing then vinyl_idx = vinyl_idx + 1 end
	local spokes = { "│", "╱", "─", "╲" }
	local spoke = is_playing and spokes[(vinyl_idx % #spokes) + 1] or "│"
	if compact then
		return {
			"   .───────.   ",
			" .'  .───.  '. ",
			"│   ( " .. spoke .. "● )   │",
			" '.  '───'  .' ",
			"   '───────'   ",
		}
	end
	return {
		"    .───────.    ",
		"  .'  .───.  '.  ",
		" ╱   ╱  " .. spoke .. "  ╲   ╲ ",
		"│   │   ●   │   │",
		" ╲   ╲  " .. spoke .. "  ╱   ╱ ",
		"  '.  '───'  .'  ",
		"    '───────'    ",
	}
end

--- Get animated vinyl art lines (4 lines, compact TUI turntable)
---@param is_playing boolean|nil
---@return string[]
function M.get_vinyl_art(is_playing)
	local disc = theme.icon("disc")
	if not is_playing then
		return {
			"╭───────╮",
			string.format("│  %s    │", disc),
			"│  💤   │",
			"╰───────╯",
		}
	end

	vinyl_idx = (vinyl_idx % #vinyl_notes) + 1
	local note = vinyl_notes[vinyl_idx]

	return {
		string.format("╭───%s───╮", note.top),
		string.format("│ %s%s%s   │", note.left, disc, note.right),
		string.format("│   %s   │", note.bottom),
		"╰───────╯",
	}
end

return M
