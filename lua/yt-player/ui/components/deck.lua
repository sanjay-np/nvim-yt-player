---@mod yt-player.ui.components.deck Framed record deck and persistent transport
local M = {}
local utils = require("yt-player.utils")
local layout = require("yt-player.ui.layout")
local theme = require("yt-player.ui.theme")
local progress = require("yt-player.ui.components.progress")
local visualizer = require("yt-player.ui.components.visualizer")

function M.repeat_label(state)
	if state.loop_file and state.loop_file ~= "no" then return "TRACK" end
	if state.loop_playlist and state.loop_playlist ~= "no" then return "QUEUE" end
	return "OFF"
end

local function timeline(state, width)
	local elapsed = utils.format_time(state.position)
	local total = (state.duration or 0) > 0 and utils.format_time(state.duration) or "--:--"
	local bar = progress.bar(state.position, state.duration, math.max(1, width - #elapsed - #total - 2), "slider")
	return utils.safe_truncate(elapsed .. " " .. bar .. " " .. total, width)
end

function M.transport(state, width)
	local controls = "[b] " .. theme.icon("prev") .. "  [Space] " .. theme.icon(state.playing and "pause" or "play") .. "  " .. theme.icon("next") .. " [n]"
	local time = utils.format_time(state.position) .. " / " .. ((state.duration or 0) > 0 and utils.format_time(state.duration) or "--:--")
	local volume = state.muted and "MUTED" or "VOL " .. math.floor(state.volume or 100) .. "%"
	local right = time .. "  " .. volume
	if width >= 100 then
		controls = controls .. "  │  " .. utils.safe_truncate(utils.resolve_title(state.title or "Nothing playing", state), width - vim.fn.strdisplaywidth(controls .. right) - 8)
	elseif width < 60 then
		controls = "[b] Prev  [Space] " .. (state.playing and "Pause" or "Play") .. "  [n] Next"
		right = time
	end
	return layout.pair(controls, right, width)
end

--- Render a real terminal deck, with artwork, transport, and optional output pane.
function M.render(state, width, opts)
	opts = opts or {}
	local tall = opts.tall == true
	local row_count = tall and 7 or 5
	local output_width = width >= 100 and 26 or 0
	local main_width = width - (output_width > 0 and output_width + 2 or 0)
	local inner = main_width - 4
	local show_art = main_width >= 60 or (opts.art and main_width >= 42)
	local art_width = show_art and (tall and 19 or 17) or 0
	local text_width = inner - (show_art and art_width + 2 or 0)
	local has_track = state.title and state.title ~= ""
	local title = has_track and utils.resolve_title(state.title, state) or "Find your next favorite track"
	local artist = has_track and (state.artist or "Unknown artist") or "/ Search YouTube   ·   Enter Play   ·   a Queue"
	local status = state.playing and "● PLAYING" or (has_track and "Ⅱ PAUSED" or "○ STANDBY")
	local style = opts.style or visualizer.current_style
	local art = visualizer.record(state.playing and style ~= "none", not tall)
	local controls = "[b] " .. theme.icon("prev") .. "   [Space] " .. theme.icon(state.playing and "pause" or "play") .. "   " .. theme.icon("next") .. " [n]"
	if text_width < 34 then controls = theme.icon("prev") .. "   [Space] " .. theme.icon(state.playing and "pause" or "play") .. "   " .. theme.icon("next") end
	local volume = state.muted and "MUTED" or "VOL " .. math.floor(state.volume or 100) .. "%"
	local settings = string.format("%s  ·  %.2fx  ·  RADIO %s", volume, state.speed or 1, state.radio_enabled and "ON" or "OFF")
	local text, groups = {}, {}
	if tall then
		local wrapped = layout.wrap(title, text_width, 2)
		text = {
			wrapped[1] or title, wrapped[2] or state.album or "YOUTUBE AUDIO",
			artist, controls, timeline(state, text_width),
			layout.pair((state.duration or 0) > 0 and "−" .. utils.format_time(math.max(0, state.duration - (state.position or 0))) .. " remaining" or "Live / unknown duration",
				#(state.playlist or {}) > 0 and string.format("TRACK %02d / %02d", math.max(1, (state.playlist_pos or 0) + 1), #state.playlist) or "QUEUE EMPTY", text_width),
			output_width > 0 and "[h/l] Seek   [+/-] Volume   [v] Visualizer" or settings .. "  ·  LOOP " .. M.repeat_label(state),
		}
		groups = { "YtPlayerTitleText", "YtPlayerMuted", "YtPlayerArtist", "YtPlayerControl", "YtPlayerProgress", "YtPlayerMuted", "YtPlayerRadio" }
	else
		text = { title, artist, controls, timeline(state, text_width), settings }
		groups = { "YtPlayerTitleText", "YtPlayerArtist", "YtPlayerControl", "YtPlayerProgress", "YtPlayerMuted" }
	end
	local output = {}
	if output_width > 0 then
		local output_inner = output_width - 4
		local spectrum_height = tall and 3 or 2
		local spectrum = visualizer.spectrum(output_inner, spectrum_height, state.playing, style)
		if style == "none" then spectrum[math.ceil(spectrum_height / 2)] = "VISUALIZER OFF" end
		for _, row in ipairs(spectrum) do table.insert(output, { row, "YtPlayerActive" }) end
		local _, gauge = progress.volume_gauge(state.muted and 0 or state.volume, output_inner - 10, state.muted)
		table.insert(output, { layout.pair(gauge, volume, output_inner), "YtPlayerVolume" })
		table.insert(output, { layout.pair("RADIO", state.radio_enabled and "ON" or "OFF", output_inner), "YtPlayerRadio" })
		table.insert(output, { layout.pair("REPEAT", M.repeat_label(state), output_inner), "YtPlayerMuted" })
		if tall then table.insert(output, { layout.pair("SPEED", string.format("%.2fx", state.speed or 1), output_inner), "YtPlayerSpeed" }) end
	end
	local lines, highlights = {}, {}
	local function span(line, group, first, last)
		table.insert(highlights, { line = line - 1, hl = group, col_start = first or 0, col_end = last or -1 })
	end
	local header = layout.rule(main_width, "NOW PLAYING", status)
	if output_width > 0 then header = header .. "  " .. layout.rule(output_width, style == "none" and "OUTPUT" or "VISUALIZER") end
	table.insert(lines, header)
	span(1, "YtPlayerFrame")
	span(1, "YtPlayerAccent", #"╭─ ", #"╭─ NOW PLAYING")
	local status_start = header:find(status, 1, true)
	if status_start then span(1, state.playing and "YtPlayerPlaying" or "YtPlayerWarning", status_start - 1, status_start - 1 + #status) end
	if output_width > 0 then
		local label = style == "none" and "OUTPUT" or "VISUALIZER"
		local start = header:find(label, 1, true)
		if start then span(1, "YtPlayerArtist", start - 1, start - 1 + #label) end
	end
	for row = 1, row_count do
		local art_text = show_art and layout.fit(art[row] or "", art_width) .. "  " or ""
		local cell = layout.inset(art_text .. layout.fit(text[row], text_width), main_width)
		local line = cell
		if output_width > 0 then line = cell .. "  " .. layout.inset((output[row] or {})[1] or "", output_width) end
		table.insert(lines, line)
		span(#lines, "YtPlayerFrame")
		span(#lines, groups[row], #"│ " + #art_text, #cell - #" │")
		if show_art then span(#lines, "YtPlayerActive", #"│ ", #"│ " + #art_text) end
		if output_width > 0 then
			span(#lines, (output[row] or {})[2] or "YtPlayerMuted", #cell + 2 + #"│ ", #line - #" │")
		end
	end
	local bottom = layout.rule(main_width, nil, nil, true)
	if output_width > 0 then bottom = bottom .. "  " .. layout.rule(output_width, nil, nil, true) end
	table.insert(lines, bottom)
	span(#lines, "YtPlayerFrame")
	return lines, highlights
end

return M
