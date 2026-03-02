---@mod yt-player.player Player UI windows
local M = {}

M.panel = { win_id = nil, buf_id = nil, update_timer = nil }
M.float = { win_id = nil, buf_id = nil, update_timer = nil }

-- Mode state: nil = normal, true = minimal
M.minimal_mode = nil

local utils = require("yt-player.utils")
local state_mod = require("yt-player.state")

-- Improved visualizer frames - cleaner, more musical look
local visualizer_frames = {
    " ▁▃▅▇▅▃▁ ", "▂▄▆█▆▄▂", "▄▆█▇█▆▄▂", "▆█▇▆▇█▆▄", "█▇▆▄▂▄▆▇",
    "▇▆▄▂▄▆▇", "▆▄▂▄▆▇▆", "▄▂▄▆▇▆▄", "▂▄▆▇▆▄▂"
}
local frame_idx = 1

-- Track panel/float window widths
local panel_width = 40
local float_width = 50

local function progress_bar(position, duration, width)
    width = width or 20
    if not duration or duration <= 0 then return string.rep("─", width) end
    local pct = math.min((position or 0) / duration, 1)
    local filled = math.floor(pct * width)
    
    -- Gradient characters for smoother look
    local gradient = {"▏","▎","▍","▌","▋","▊","▉","█"}
    local grad_idx = math.min(math.floor(pct * #gradient) + 1, #gradient)
    local fill_char = gradient[grad_idx]

    if filled == 0 then
        return "○" .. string.rep("─", width - 1)
    elseif filled >= width then
        return string.rep("█", width - 1) .. "●"
    else
        return string.rep("█", filled) .. "▌" .. string.rep("─", width - filled - 1)
    end
end

local function mini_progress_bar(position, duration, width)
    width = width or 15
    if not duration or duration <= 0 then return string.rep("─", width) end
    local pct = math.min((position or 0) / duration, 1)
    local filled = math.floor(pct * width)
    if filled == 0 then
        return "○" .. string.rep("─", width - 1)
    elseif filled >= width then
        return string.rep("━", width - 1) .. "●"
    else
        return string.rep("━", filled) .. "○" .. string.rep("─", width - filled - 1)
    end
end

local function volume_bar(volume, width)
    width = width or 8
    local filled = math.floor(math.min(math.max(volume or 100, 0), 100) / 100 * width)
    local chars = {"▏","▎","▍","▌","▋","▊","▉","█"}
    local result = ""
    for i = 1, width do
        if i <= filled then
            local grad_idx = math.min(math.floor((i / width) * #chars) + 1, #chars)
            result = result .. chars[grad_idx]
        else
            result = result .. "░"
        end
    end
    return result
end

local function safe_truncate(str, max_width)
    if not str then return "" end
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
    str = safe_truncate(str or "", width)
    local len = vim.fn.strdisplaywidth(str)
    local left = math.floor((width - len) / 2)
    local right = width - len - left
    return string.rep(" ", left) .. str .. string.rep(" ", right)
end

local function pad_right(str, width)
    str = safe_truncate(str or "", width)
    local len = vim.fn.strdisplaywidth(str)
    return str .. string.rep(" ", width - len)
end

-- Get actual window width for dynamic sizing
local function get_win_width(win_id)
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        return vim.api.nvim_win_get_width(win_id)
    end
    return nil
end

-- Determine target width based on window
local function get_target_width(is_float)
    if is_float then
        return float_width
    else
        return panel_width
    end
end

-- Update stored width from actual window
local function update_stored_width(win_id, is_float)
    local w = get_win_width(win_id)
    if w and w > 10 then
        if is_float then
            float_width = w
        else
            panel_width = w
        end
    end
end

local function build_lines(state, is_float)
    local is_playing = state.playing
    local width = get_target_width(is_float)
    local use_minimal = M.minimal_mode

    -- Animate visualizer if playing
    if is_playing then
        frame_idx = (frame_idx % #visualizer_frames) + 1
    end

    local vis = is_playing and visualizer_frames[frame_idx] or "         "
    local title = state.title or "No Track"
    local artist = state.artist or "Unknown Artist"
    if artist == "" then artist = "Unknown Artist" end

    local vol = math.floor(state.volume or 100)
    local speed_str = string.format("%.1fx", state.speed or 1)

    local pos_str = utils.format_time(state.position)
    local dur_str = utils.format_time(state.duration)
    local pct = (state.duration and state.duration > 0)
        and string.format("%d%%", math.floor((state.position or 0) / state.duration * 100))
        or "0%"

    local lines = {}
    
    -- Helper to add bordered row
    local function add_row(content)
        table.insert(lines, string.format(" │ %s │", pad_right(content, width - 4)))
    end
    local function add_center(content)
        table.insert(lines, string.format(" │ %s │", center_text(content, width - 4)))
    end

    -- ╭─ Header ───────────────────────╮
    local header = string.format(" ╭─ %s ", title)
    header = header .. string.rep("─", width - vim.fn.strdisplaywidth(header) - 1) .. "╮"
    table.insert(lines, header)
    
    -- Visualizer + Track info row
    if use_minimal then
        -- Minimal: title + mini progress on one line
        local mini_prog = mini_progress_bar(state.position, state.duration, width - 25)
        add_row(string.format("♫ %s %s %s", safe_truncate(title, width - 30), mini_prog, pct))
    else
        -- Normal: full visualizer + track info
        add_center("▃▅▆  " .. vis .. "  ▆▅▃")
        add_row("♪ " .. safe_truncate(title, width - 8))
        add_row("• " .. safe_truncate(artist, width - 6))
        
        -- Progress line
        local prog_bar = progress_bar(state.position, state.duration, width - 22)
        local prog_line = string.format("%s %s %s", pos_str, prog_bar, dur_str)
        add_row(prog_line)
        
        -- Controls
        local ctrl_icon = is_playing and "⏸" or "▶"
        local ctrl = string.format("[b]◀ [%s] ▶[n]    [p/s] %s  [m]Mute", ctrl_icon, ctrl_icon)
        add_center(ctrl)
        
        -- Volume & Speed
        local vol_icon = (state.muted or vol == 0) and "🔇" or (vol > 50 and "🔊" or "🔉")
        local vol_line = string.format("%s %d%% %s  ⏩ %s", vol_icon, vol, volume_bar(vol, 6), speed_str)
        add_row(vol_line)
        
        -- Radio mode indicator
        local radio_on = pcall(function()
            return require("yt-player.radio").enabled
        end) and require("yt-player.radio").enabled
        if radio_on then
            add_center("📻 Radio Mode")
        end
    end

    -- ╰─ Footer ───────────────────────╯
    local footer = " ╰" .. string.rep("─", width - 2) .. "╯"
    table.insert(lines, footer)

    -- Compact help (2 lines instead of 6)
    if not use_minimal then
        table.insert(lines, " ╭─ Controls ───────────────────────╮")
        table.insert(lines, " │ [p/s/t]Play [b/n]Prev/Nxt [m]Mute │")
        table.insert(lines, " │ [h/l]±5s [H/L]±30s [+/-]Vol      │")
        table.insert(lines, " │ [</>]Speed [r]Radio [q]Close     │")
        table.insert(lines, " ╰" .. string.rep("─", width - 2) .. "╯")
    end

    -- Compact Queue
    if state.playlist and #state.playlist > 0 then
        local count_txt = string.format("%d/%d", (state.playlist_pos or 0) + 1, #state.playlist)
        
        -- Queue header - more compact
        local qheader = string.format(" ╭─ Queue (%s)", count_txt)
        qheader = qheader .. string.rep("─", width - vim.fn.strdisplaywidth(qheader) - 1) .. "╮"
        table.insert(lines, qheader)

        local limit = use_minimal and 3 or (require("yt-player").config.player.queue_display_limit or 4)
        local start_idx = math.max(1, (state.playlist_pos or 0))
        local end_idx = math.min(#state.playlist, start_idx + limit - 1)

        for i = start_idx, end_idx do
            local item = state.playlist[i]
            local prefix = (i - 1 == state.playlist_pos) and "▸" or " "
            local item_title = item.title or (state.playlist_meta and state.playlist_meta[item.filename]) or
                item.filename or "Unknown"
            
            -- Compact queue item: "▸ 1. Title..." or "  2. Title..."
            local qitem = string.format("%s %d. %s", prefix, i, safe_truncate(item_title, width - 10))
            add_row(qitem)
        end

        if end_idx < #state.playlist then
            add_row(string.format("  +%d more", #state.playlist - end_idx))
        end
        table.insert(lines, " ╰" .. string.rep("─", width - 2) .. "╯")
    end

    return lines
end

local function calc_width(lines)
    local max = 0
    for _, line in ipairs(lines) do
        local w = vim.fn.strdisplaywidth(line)
        if w > max then max = w end
    end
    return math.max(max, 30)
end

local function refresh_instance(inst, is_float)
    if not inst.buf_id or not vim.api.nvim_buf_is_valid(inst.buf_id) then return false end
    if not inst.win_id or not vim.api.nvim_win_is_valid(inst.win_id) then return false end

    -- Update stored width from actual window
    update_stored_width(inst.win_id, is_float)
    
    local lines = build_lines(state_mod.get_current(), is_float)
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
    vim.keymap.set("n", "r", function()
        require("yt-player.radio").toggle(); refresh()
    end, o)
    -- Toggle minimal mode
    vim.keymap.set("n", "M", function()
        M.minimal_mode = not M.minimal_mode
        refresh()
    end, o)
end

---------- PANEL ----------

function M.open_panel()
    if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then
        refresh_panel()
        vim.api.nvim_set_current_win(M.panel.win_id)
        return
    end

    local lines = build_lines(state_mod.get_current(), false)

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
    
    -- Get actual panel width after creation
    panel_width = vim.api.nvim_win_get_width(M.panel.win_id)

    vim.wo[M.panel.win_id].cursorline = false
    vim.wo[M.panel.win_id].number = false
    vim.wo[M.panel.win_id].relativenumber = false
    vim.wo[M.panel.win_id].signcolumn = "no"
    vim.wo[M.panel.win_id].wrap = false
    vim.wo[M.panel.win_id].winfixwidth = true -- Prevent width from changing on layout resize

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

    local lines = build_lines(state_mod.get_current(), true)
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

-- Toggle minimal mode (press M in player)
function M.toggle_minimal()
    M.minimal_mode = not M.minimal_mode
    if M.panel.win_id and vim.api.nvim_win_is_valid(M.panel.win_id) then
        refresh_panel()
    end
    if M.float.win_id and vim.api.nvim_win_is_valid(M.float.win_id) then
        refresh_float()
    end
    return M.minimal_mode
end

-- Check if minimal mode is active
function M.is_minimal()
    return M.minimal_mode == true
end

return M
