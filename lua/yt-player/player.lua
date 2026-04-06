---@mod yt-player.player Player UI windows
local M = {}

M.panel = { win_id = nil, buf_id = nil, update_timer = nil }
M.float = { win_id = nil, buf_id = nil, update_timer = nil }

-- Mode state: nil = normal, true = minimal
M.minimal_mode = nil

-- Highlights setup flag
M.highlights_setup = false

-- Module configuration (can be overridden via M.setup())
M.config = {
    show_visualizer = true,
    show_help = true,
    show_queue = true,
    queue_limit = 5,
    animate = true,
    colors = true,
}

-- Setup function to override config
function M.setup(user_config)
    if user_config then
        M.config = vim.tbl_deep_extend("force", M.config, user_config)
    end
end

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

-- Proper border width calculation
local function make_header(title, width)
    local content = "─ " .. title .. " ─"
    local remaining = width - vim.fn.strdisplaywidth(content) - 2
    if remaining > 0 then
        content = content .. string.rep("─", remaining)
    end
    return "╭" .. content .. "╮"
end

local function make_footer(width)
    return "╰" .. string.rep("─", width - 2) .. "╯"
end

local function make_section_header(title, width)
    local content = "─ " .. title
    local remaining = width - vim.fn.strdisplaywidth(content) - 2
    if remaining > 0 then
        content = content .. string.rep("─", remaining)
    end
    return "╭" .. content .. "╮"
end

-- Setup highlight groups (Dracula-inspired colors for dark theme)
local function setup_highlights()
    -- Only setup once
    if M.highlights_setup then return end
    
    -- Check if terminal supports true color
    if not vim.opt.termguicolors then return end
    
    local highlights = {
        YtPlayerTitle = { fg = "#bd93f9", bold = true },      -- Purple
        YtPlayerArtist = { fg = "#6272a4" },                  -- Grayish blue
        YtPlayerProgress = { fg = "#50fa7b" },                -- Green
        YtPlayerProgressBg = { fg = "#44475a" },              -- Dark gray
        YtPlayerControls = { fg = "#8be9fd" },                -- Cyan
        YtPlayerVolume = { fg = "#ffb86c" },                  -- Orange
        YtPlayerRadio = { fg = "#ff79c6" },                   -- Pink
        YtPlayerQueue = { fg = "#f8f8f2" },                   -- White
        YtPlayerQueueCurrent = { fg = "#50fa7b", bold = true }, -- Green bold
        YtPlayerBorder = { fg = "#6272a4" },                  -- Gray border
        YtPlayerHelp = { fg = "#6272a4" },                    -- Gray help
    }
    
    for name, opts in pairs(highlights) do
        vim.api.nvim_set_hl(0, name, opts)
    end
    
    M.highlights_setup = true
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
    local content_width = width - 4

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
    local highlights = {} -- Store highlights for each line
    
    -- Helper to add bordered row with optional highlight
    local function add_row(content, highlight)
        table.insert(lines, string.format("│ %s │", pad_right(content, content_width)))
        if highlight and M.config.colors then
            table.insert(highlights, { line = #lines - 1, hl = highlight })
        end
    end
    local function add_center(content, highlight)
        table.insert(lines, string.format("│ %s │", center_text(content, content_width)))
        if highlight and M.config.colors then
            table.insert(highlights, { line = #lines - 1, hl = highlight })
        end
    end

    -- ╭─ Header ───────────────────────╮
    -- LAYER 1: Track title + artist - PROMINENT
    if use_minimal then
        -- Minimal: title + mini progress on one line
        local mini_prog = mini_progress_bar(state.position, state.duration, width - 25)
        table.insert(lines, make_header("Now Playing", width))
        add_row(string.format("♫ %s %s %s", safe_truncate(title, width - 30), mini_prog, pct))
    else
        -- Normal: Full visual hierarchy
        table.insert(lines, make_header("Now Playing", width))
        
        -- Album Art Placeholder (left side) + Track Info (right side)
        -- All lines must be exactly 7 chars for proper alignment
        local album_art = {
            "[~~~~~]",
            "[Album]",
            "[ Art ]",
            "-------",
        }
        
        -- Calculate split: album art + track info
        local art_width = 7
        local info_width = content_width - art_width - 1
        
        -- Add album art + track info row
        for i, art_line in ipairs(album_art) do
            local info_line = ""
            if i == 1 then
                info_line = safe_truncate(title, info_width)
            elseif i == 2 then
                info_line = safe_truncate(artist, info_width)
            elseif i == 3 then
                -- Duration info
                info_line = string.format("⏱ %s / %s", pos_str, dur_str)
            elseif i == 4 then
                -- View count / playlist info if available
                if state.view_count then
                    info_line = string.format("👁 %s views", state.view_count)
                elseif state.playlist_name then
                    info_line = "📋 " .. safe_truncate(state.playlist_name, info_width - 2)
                else
                    info_line = ""
                end
            else
                info_line = ""
            end
            table.insert(lines, string.format("│ %s %s │", art_line, pad_right(info_line, info_width)))
        end
        
        -- Visualizer
        if M.config.show_visualizer then
            add_center("▃▅▆  " .. vis .. "  ▆▅▃")
        end

        -- Layer 2: Playback status + progress
        local prog_bar = progress_bar(state.position, state.duration, width - 22)
        local prog_line = string.format("%s %s %s", pos_str, prog_bar, dur_str)
        add_row(prog_line)

        -- Layer 3: Volume + Speed (secondary info)
        local vol_icon = (state.muted or vol == 0) and "🔇" or (vol > 50 and "🔊" or "🔉")
        local vol_line = string.format("%s %d%%  ⏩ %s", vol_icon, vol, speed_str)
        add_row(vol_line)

        -- Controls: compact icons
        local ctrl_icon = is_playing and "⏸" or "▶"
        local ctrl = string.format("⏮ │ %s │ ⏭    %s │ 🔀", ctrl_icon, vol_icon)
        add_center(ctrl)

        -- Radio mode indicator
        local radio_on = pcall(function()
            return require("yt-player.radio").enabled
        end) and require("yt-player.radio").enabled
        if radio_on then
            add_center("📻 Radio Mode")
        end
    end

    -- Footer
    table.insert(lines, make_footer(width))

    -- Layer 4: Help section - reduced to 1 line (conditional)
    if not use_minimal and M.config.show_help then
        table.insert(lines, make_section_header("Controls", width))
        add_row("[p/s/t]Play [b/n]Nav [m]Vol [</>]Speed [0-9]Seek [r]Radio [q]Exit")
        table.insert(lines, make_footer(width))
    end

    -- Compact Queue with duration (conditional)
    if M.config.show_queue and state.playlist and #state.playlist > 0 then
        local count_txt = string.format("%d/%d", (state.playlist_pos or 0) + 1, #state.playlist)
        
        table.insert(lines, make_section_header("Queue (" .. count_txt .. ")", width))

        local limit = use_minimal and 3 or M.config.queue_limit
        local start_idx = math.max(1, (state.playlist_pos or 0))
        local end_idx = math.min(#state.playlist, start_idx + limit - 1)

        for i = start_idx, end_idx do
            local item = state.playlist[i]
            local is_current = (i - 1 == state.playlist_pos)
            local prefix = is_current and "▸" or "│"
            local item_title = item.title or (state.playlist_meta and state.playlist_meta[item.filename]) or
                item.filename or "Unknown"
            
            -- Get duration if available
            local dur = item.duration or (item.length_sec)
            local dur_str = dur and utils.format_time(dur) or ""
            
            -- Format: "▸ 1. Track Title        3:45" or "│ 2. Track Title        3:45"
            local qitem = string.format("%s %d. %s%s", prefix, i, 
                pad_right(safe_truncate(item_title, width - 16), width - 16),
                dur_str)
            add_row(qitem)
            
            -- Visual separator after current track
            if is_current and i < end_idx then
                add_row(pad_right("├" .. string.rep("─", content_width - 1), content_width))
            end
        end

        if end_idx < #state.playlist then
            add_row(string.format("│ +%d more", #state.playlist - end_idx))
        end
        table.insert(lines, make_footer(width))
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
    
    -- Keyboard seeking: 0-9 jump to 0%-90%, G goes to end
    for i = 0, 9 do
        local pct = i * 10
        vim.keymap.set("n", tostring(i), function()
            require("yt-player").command({ "seek", pct, "percent" })
            vim.defer_fn(refresh, 200)
        end, o)
    end
    vim.keymap.set("n", "G", function()
        require("yt-player").command({ "seek", 100, "percent" })
        vim.defer_fn(refresh, 200)
    end, o)
    
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
    -- Setup highlights if enabled
    if M.config.colors then
        setup_highlights()
    end
    
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
    -- Setup highlights if enabled
    if M.config.colors then
        setup_highlights()
    end
    
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
    })

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
