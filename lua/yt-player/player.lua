---@mod yt-player.player Player UI windows
local M = {}

M.panel = { win_id = nil, buf_id = nil, update_timer = nil }
M.float = { win_id = nil, buf_id = nil, update_timer = nil }

local utils = require("yt-player.utils")
local state_mod = require("yt-player.state")

local visualizer_frames = {
    " ▂▄▆█▆▄▂ ", "▂▄▆█▇█▆▄▂", "▄▆█▇▆▇█▆▄", "▆█▇▆▄▆▇█▆", "█▇▆▄▂▄▆▇█",
    "▇▆▄▂ ▂▄▆▇", "▆▄▂   ▂▄▆", "▄▂     ▂▄", "▂       ▂"
}
local frame_idx = 1

local function progress_bar(position, duration, width)
    width = width or 24
    if not duration or duration <= 0 then return string.rep("─", width) end
    local pct = math.min((position or 0) / duration, 1)
    local filled = math.floor(pct * width)

    if filled == 0 then
        return "●" .. string.rep("─", width - 1)
    elseif filled >= width then
        return string.rep("─", width - 1) .. "●"
    else
        return string.rep("─", filled) .. "●" .. string.rep("─", width - filled - 1)
    end
end

local function volume_bar(volume, width)
    width = width or 10
    local filled = math.floor(math.min(math.max(volume or 100, 0), 100) / 100 * width)
    return string.rep("█", filled) .. string.rep("░", width - filled)
end

local function safe_truncate(str, max_width)
    local width = vim.fn.strdisplaywidth(str)
    if width <= max_width then return str end

    local chars = vim.fn.strchars(str)
    local truncated = str
    while vim.fn.strdisplaywidth(truncated) > max_width and chars > 0 do
        chars = chars - 1
        truncated = vim.fn.strcharpart(str, 0, chars)
    end
    return truncated
end

local function center_text(str, width)
    str = safe_truncate(str, width)
    local len = vim.fn.strdisplaywidth(str)
    local left = math.floor((width - len) / 2)
    local right = width - len - left
    return string.rep(" ", left) .. str .. string.rep(" ", right)
end

local function pad_right(str, width)
    str = safe_truncate(str, width)
    local len = vim.fn.strdisplaywidth(str)
    return str .. string.rep(" ", width - len)
end

local function build_lines(state)
    local is_playing = state.playing

    -- Animate visualizer if playing
    if is_playing then
        frame_idx = (frame_idx % #visualizer_frames) + 1
    end

    local vis = is_playing and visualizer_frames[frame_idx] or "         "
    local title = state.title or "No Track"
    local artist = state.artist or "Unknown Artist"
    if artist == "" then artist = "Unknown Artist" end

    local vol = math.floor(state.volume or 100)
    local speed_str = string.format("%.2gx", state.speed or 1)

    local pos_str = utils.format_time(state.position)
    local dur_str = utils.format_time(state.duration)
    local pct = (state.duration and state.duration > 0)
        and string.format("%d%%", math.floor((state.position or 0) / state.duration * 100))
        or "0%"

    local lines = {}
    local function add_row(content)
        table.insert(lines, string.format(" │ %s │", pad_right(content, 40)))
    end
    local function add_center(content)
        table.insert(lines, string.format(" │ %s │", center_text(content, 40)))
    end

    table.insert(lines, " ╭──────────────────────────────────────────╮")
    add_center("▃▅▆▇  " .. vis .. "  ▇▆▅▃")
    add_row("")
    add_row("  ♪  " .. title)
    add_row("  •  " .. artist)
    add_row("")

    local prog_line = string.format("  %s %s %s [%s]", pos_str, progress_bar(state.position, state.duration, 15), dur_str,
        pct)
    add_row(prog_line)
    add_row("")

    -- Controls
    local ctrl_str = is_playing and "||" or "▶"
    add_center("|<      " .. ctrl_str .. "      >|")
    add_row("")

    local bottom_stats = string.format("  Vol %d%% [%s]     Spd %s", vol, volume_bar(vol, 10), speed_str)
    add_row(bottom_stats)
    table.insert(lines, " ╰──────────────────────────────────────────╯")

    -- Help Menu
    table.insert(lines, " ╭─ Controls ───────────────────────────────╮")
    table.insert(lines, " │ [p/s/t] Play/Pause    [m] Mute           │")
    table.insert(lines, " │ [b/n] Prev/Next       [-/+] Volume       │")
    table.insert(lines, " │ [h/l] Seek ±5s        [</>] Speed        │")
    table.insert(lines, " │ [H/L] Seek ±30s       [q] Close          │")
    table.insert(lines, " ╰──────────────────────────────────────────╯")

    -- Queue
    if state.playlist and #state.playlist > 0 then
        local count_txt = string.format("(%d/%d)", (state.playlist_pos or 0) + 1, #state.playlist)
        local top_border = string.format(" ╭─ Queue %s%s╮", count_txt, string.rep("─", 32 - #count_txt))
        table.insert(lines, top_border)

        local limit = require("yt-player").config.player.queue_display_limit or 5
        local start_idx = math.max(1, (state.playlist_pos or 0) - 1)
        local end_idx = math.min(#state.playlist, start_idx + limit - 1)

        for i = start_idx, end_idx do
            local item = state.playlist[i]
            local prefix = (i - 1 == state.playlist_pos) and " > " or "   "
            local item_title = item.title or (state.playlist_meta and state.playlist_meta[item.filename]) or
                item.filename or "Unknown"

            local queue_item = string.format("%s%d. %s", prefix, i, item_title)
            add_row(queue_item)
        end

        if end_idx < #state.playlist then
            add_row(string.format("   ... and %d more", #state.playlist - end_idx))
        end
        table.insert(lines, " ╰──────────────────────────────────────────╯")
    end

    return lines
end

local function calc_width(lines)
    local max = 0
    for _, line in ipairs(lines) do
        local w = vim.fn.strdisplaywidth(line)
        if w > max then max = w end
    end
    return math.max(max + 4, 40)
end

local function refresh_instance(inst, is_float)
    if not inst.buf_id or not vim.api.nvim_buf_is_valid(inst.buf_id) then return false end
    if not inst.win_id or not vim.api.nvim_win_is_valid(inst.win_id) then return false end

    local lines = build_lines(state_mod.get_current())
    vim.bo[inst.buf_id].modifiable = true
    vim.api.nvim_buf_set_lines(inst.buf_id, 0, -1, false, lines)
    vim.bo[inst.buf_id].modifiable = false

    if is_float then
        vim.api.nvim_win_set_config(inst.win_id, { width = calc_width(lines), height = #lines })
    end
    return true
end

local function refresh_panel()
    if not refresh_instance(M.panel, false) then M.close_panel() end
end

local function refresh_float()
    if not refresh_instance(M.float, true) then M.close_float() end
end

local function setup_keymaps(buf, is_float)
    local o = { noremap = true, silent = true, buffer = buf }
    local refresh = is_float and refresh_float or refresh_panel
    local close = is_float and M.close_float or M.close_panel
    local cmd = function(c)
        return function()
            require("yt-player").command(c); vim.defer_fn(refresh, 200)
        end
    end

    vim.keymap.set("n", "q", close, o)
    vim.keymap.set("n", "<Esc>", close, o)
    vim.keymap.set("n", "p", cmd({ "set_property", "pause", false }), o)
    vim.keymap.set("n", "s", cmd({ "set_property", "pause", true }), o)
    vim.keymap.set("n", "t", cmd({ "cycle", "pause" }), o)
    vim.keymap.set("n", "n",
        function()
            require("yt-player").command({ "playlist-next", "weak" })
            vim.defer_fn(refresh, 500)
        end, o)
    vim.keymap.set("n", "b",
        function()
            require("yt-player").command({ "playlist-prev", "weak" })
            vim.defer_fn(refresh, 500)
        end, o)
    vim.keymap.set("n", "m", cmd({ "cycle", "mute" }), o)
    vim.keymap.set("n", ">", cmd({ "add", "speed", 0.25 }), o)
    vim.keymap.set("n", "<", cmd({ "add", "speed", -0.25 }), o)
    vim.keymap.set("n", "+", cmd({ "add", "volume", 5 }), o)
    vim.keymap.set("n", "-", cmd({ "add", "volume", -5 }), o)
    vim.keymap.set("n", "l", cmd({ "seek", 5, "relative" }), o)
    vim.keymap.set("n", "h", cmd({ "seek", -5, "relative" }), o)
    vim.keymap.set("n", "L", cmd({ "seek", 30, "relative" }), o)
    vim.keymap.set("n", "H", cmd({ "seek", -30, "relative" }), o)
end

---------- PANEL ----------

function M.open_panel()
    if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then
        refresh_panel()
        vim.api.nvim_set_current_win(M.panel.win_id)
        return
    end

    local lines = build_lines(state_mod.get_current())

    M.panel.buf_id = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(M.panel.buf_id, 0, -1, false, lines)
    vim.bo[M.panel.buf_id].modifiable = false
    vim.bo[M.panel.buf_id].bufhidden = "wipe"
    vim.bo[M.panel.buf_id].buftype = "nofile"
    vim.bo[M.panel.buf_id].filetype = "yt-player-player"
    vim.bo[M.panel.buf_id].swapfile = false

    vim.cmd("botright 45vsplit")
    M.panel.win_id = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(M.panel.win_id, M.panel.buf_id)

    vim.wo[M.panel.win_id].cursorline = false
    vim.wo[M.panel.win_id].number = false
    vim.wo[M.panel.win_id].relativenumber = false
    vim.wo[M.panel.win_id].signcolumn = "no"
    vim.wo[M.panel.win_id].wrap = false

    setup_keymaps(M.panel.buf_id, false)

    M.panel.update_timer = vim.loop.new_timer()
    M.panel.update_timer:start(200, 200, vim.schedule_wrap(function()
        if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then refresh_panel() else M.close_panel() end
    end))

    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = M.panel.buf_id,
        once = true,
        callback = function()
            if M.panel.update_timer then
                pcall(function()
                    M.panel.update_timer:stop(); M.panel.update_timer:close()
                end)
            end
            M.panel.update_timer = nil
            M.panel.win_id = nil
            M.panel.buf_id = nil
        end,
    })
end

function M.close_panel()
    if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then
        vim.api.nvim_win_close(M.panel.win_id, true)
    end
end

function M.toggle_panel()
    if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then M.close_panel() else M.open_panel() end
end

---------- FLOAT ----------

function M.open_float()
    if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) then
        refresh_float()
        vim.api.nvim_set_current_win(M.float.win_id)
        return
    end

    local lines = build_lines(state_mod.get_current())
    local width, height = calc_width(lines), #lines

    M.float.buf_id = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(M.float.buf_id, 0, -1, false, lines)
    vim.bo[M.float.buf_id].modifiable = false
    vim.bo[M.float.buf_id].bufhidden = "wipe"
    vim.bo[M.float.buf_id].buftype = "nofile"
    vim.bo[M.float.buf_id].filetype = "yt-player-player"
    vim.bo[M.float.buf_id].swapfile = false

    M.float.win_id = vim.api.nvim_open_win(M.float.buf_id, true, {
        relative = "editor",
        row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
        col = math.max(0, math.floor((vim.o.columns - width) / 2)),
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " 🎵 YT Control ",
        title_pos = "center",
    })

    vim.wo[M.float.win_id].winblend = 10
    vim.wo[M.float.win_id].cursorline = false

    setup_keymaps(M.float.buf_id, true)

    M.float.update_timer = vim.loop.new_timer()
    M.float.update_timer:start(1000, 1000, vim.schedule_wrap(function()
        if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) then refresh_float() else M.close_float() end
    end))

    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = M.float.buf_id,
        once = true,
        callback = function()
            if M.float.update_timer then
                pcall(function()
                    M.float.update_timer:stop(); M.float.update_timer:close()
                end)
            end
            M.float.update_timer = nil
            M.float.win_id = nil
            M.float.buf_id = nil
        end,
    })
end

function M.close_float()
    if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) then
        vim.api.nvim_win_close(M.float.win_id, true)
    end
end

function M.toggle_float()
    if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) then M.close_float() else M.open_float() end
end

return M
