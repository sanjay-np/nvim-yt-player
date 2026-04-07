---@mod yt-player.search YouTube search via yt-dlp
local M = {}

-- =============================================================================
-- HIGHLIGHTS
-- =============================================================================

local ns = "yt-player-search"

--- Setup custom highlight groups for search UI
function M.setup_highlights()
    ns = vim.api.nvim_create_namespace(ns)

    -- Get colorscheme-agnostic colors (fallback to catppuccin-like)
    local colors = {
        prompt = "#89b4fa",       -- Blue
        input = "#cdd6f4",        -- White
        mode = "#f9e2af",         -- Yellow
        index = "#6c7086",        -- Gray
        title = "#cdd6f4",        -- White
        channel = "#a6adc8",      -- Light gray
        duration = "#f38ba8",     -- Red
        selected_bg = "#313244",  -- Dark gray
        selected_fg = "#f5e0dc",  -- Light
        playing = "#a6e3a1",      -- Green
        loading = "#f9e2af",      -- Yellow
        error = "#f38ba8",        -- Red
        empty = "#6c7086",        -- Gray
        footer = "#585b70",       -- Dark gray
        hotkey = "#94e2d5",       -- Teal
        border = "#45475a",       -- Border
    }

    -- Try to detect user's colorscheme colors
    local ok, hl = pcall(vim.api.nvim_get_hl_by_name, "Normal", true)
    if ok and hl.foreground then
        colors.input = string.format("#%06x", hl.foreground)
        colors.title = colors.input
    end
    ok, hl = pcall(vim.api.nvim_get_hl_by_name, "Comment", true)
    if ok and hl.foreground then
        colors.channel = string.format("#%06x", hl.foreground)
        colors.footer = colors.channel
    end

    -- Define highlights
    local highlights = {
        YTSearchPrompt = { fg = colors.prompt, bold = true },
        YTSearchInput = { fg = colors.input },
        YTSearchMode = { fg = colors.mode, bold = true },
        YTSearchIndex = { fg = "#7f849c" },
        YTSearchTitle = { fg = colors.title, bold = true },
        YTSearchChannel = { fg = colors.channel },
        YTSearchDuration = { fg = colors.duration },
        YTSearchSelected = { fg = colors.selected_fg, bg = colors.selected_bg, bold = true },
        YTSearchSelectedTitle = { fg = "#cba6f7", bg = colors.selected_bg, bold = true },
        YTSearchSelectedMeta = { fg = "#a6adc8", bg = colors.selected_bg },
        YTSearchSelectedDur = { fg = colors.duration, bg = colors.selected_bg, bold = true },
        YTSearchAccent = { fg = "#cba6f7", bg = colors.selected_bg, bold = true },
        YTSearchPlaying = { fg = colors.playing, bold = true },
        YTSearchPlayingTitle = { fg = colors.playing, bold = true },
        YTSearchPlayingMeta = { fg = colors.playing },
        YTSearchPlayingBadge = { fg = "#1e1e2e", bg = colors.playing, bold = true },
        YTSearchLoading = { fg = colors.loading, italic = true },
        YTSearchError = { fg = colors.error, bold = true },
        YTSearchEmpty = { fg = colors.empty, italic = true },
        YTSearchFooter = { fg = colors.footer },
        YTSearchHotkey = { fg = colors.hotkey, bold = true },
        YTSearchBorder = { fg = colors.border },
        YTSearchSeparator = { fg = "#313244" },
        YTSearchResultCount = { fg = colors.index, italic = true },
    }

    for name, opts in pairs(highlights) do
        vim.api.nvim_set_hl(0, name, opts)
    end
end

-- Auto-setup highlights when module loads
M.setup_highlights()

-- =============================================================================
-- SEARCH
-- =============================================================================

--- Search YouTube asynchronously using yt-dlp
--- Returns results via callback: list of { title, url, duration, channel, id }
---@param query string  Search query
---@param count number|nil  Number of results (default 10)
---@param callback fun(results: table[], err: string|nil)
function M.search(query, count, callback)
    count = count or 10

    if vim.fn.executable("yt-dlp") == 0 then
        callback({}, "yt-dlp is not installed or not in PATH")
        return
    end

    local search_url = string.format("ytsearch%d:%s", count, query)
    local args = {
        "yt-dlp",
        "--flat-playlist",
        "--dump-json",
        "--no-warnings",
        "--no-download",
        search_url,
    }

    local stderr_chunks = {}
    local results = {}

    local stdout = vim.loop.new_pipe(false)
    local stderr = vim.loop.new_pipe(false)

    local handle
    handle = vim.loop.spawn(args[1], {
        args = vim.list_slice(args, 2),
        stdio = { nil, stdout, stderr },
    }, function(code)
        -- Close all handles
        if stdout then
            pcall(function()
                stdout:read_stop()
                stdout:close()
            end)
        end
        if stderr then
            pcall(function()
                stderr:read_stop()
                stderr:close()
            end)
        end
        if handle then
            pcall(function()
                handle:close()
            end)
        end

        vim.schedule(function()
            if code ~= 0 then
                callback({}, table.concat(stderr_chunks, ""))
                return
            end

            callback(results, nil)
        end)
    end)

    if not handle then
        if stdout then
            pcall(function()
                stdout:close()
            end)
        end
        if stderr then
            pcall(function()
                stderr:close()
            end)
        end
        callback({}, "Failed to spawn yt-dlp")
        return
    end

    local partial_stdout = ""
    stdout:read_start(function(_, data)
        if data then
            partial_stdout = partial_stdout .. data
            local pos = 1
            while true do
                local newline = partial_stdout:find("\n", pos)
                if not newline then break end
                
                local line = partial_stdout:sub(pos, newline - 1)
                pos = newline + 1
                
                local ok, item = pcall(vim.json.decode, line)
                if ok and type(item) == "table" then
                    local duration = 0
                    if type(item.duration) == "number" then
                        duration = item.duration
                    elseif type(item.duration) == "string" then
                        duration = tonumber(item.duration) or 0
                    end

                    results[#results + 1] = {
                        title = type(item.title) == "string" and item.title or "Unknown",
                        url = type(item.webpage_url) == "string" and item.webpage_url
                            or (type(item.url) == "string" and item.url or ""),
                        id = type(item.id) == "string" and item.id or "",
                        duration = duration,
                        channel = type(item.channel) == "string" and item.channel
                            or (type(item.uploader) == "string" and item.uploader or ""),
                    }
                end
            end
            if pos > 1 then
                partial_stdout = partial_stdout:sub(pos)
            end
        end
    end)

    stderr:read_start(function(_, data)
        if data then
            stderr_chunks[#stderr_chunks + 1] = data
        end
    end)

    return handle
end

--- Fetch a full YouTube playlist and seamlessly append all tracks to the mpv queue
---@param url string  Playlist URL
function M.fetch_playlist(url)
    if vim.fn.executable("yt-dlp") == 0 then
        vim.notify("YT Control: yt-dlp is not installed", vim.log.levels.ERROR)
        return
    end

    local mpv = require("yt-player.mpv")
    local state_mod = require("yt-player.state")

    -- Make sure mpv is running first so we can queue to it
    if not mpv.is_running() then
        mpv.start()
    end

    vim.notify("YT Control: Fetching playlist...", vim.log.levels.INFO)

    local args = {
        "yt-dlp",
        "--flat-playlist",
        "--dump-json",
        "--no-warnings",
        url,
    }

    local stdout = vim.loop.new_pipe(false)
    local handle

    handle = vim.loop.spawn(args[1], {
        args = vim.list_slice(args, 2),
        stdio = { nil, stdout, nil },
    }, function(code)
        if stdout then
            pcall(function()
                stdout:read_stop()
                stdout:close()
            end)
        end
        if handle then
            pcall(function()
                handle:close()
            end)
        end

        vim.schedule(function()
            if code == 0 then
                vim.notify("YT Control: Finished queuing playlist!", vim.log.levels.INFO)
            else
                vim.notify("YT Control: Failed to fetch playlist", vim.log.levels.ERROR)
            end
        end)
    end)

    if not handle then
        if stdout then
            pcall(function()
                stdout:close()
            end)
        end
        return
    end

    local partial = ""
    stdout:read_start(function(_, data)
        if data then
            partial = partial .. data
            local pos = 1
            while true do
                local newline = partial:find("\n", pos)
                if not newline then break end

                local line = partial:sub(pos, newline - 1)
                pos = newline + 1

                local ok, item = pcall(vim.json.decode, line)
                if ok and type(item) == "table" then
                    local item_url = type(item.webpage_url) == "string" and item.webpage_url
                        or (type(item.url) == "string" and item.url or "")
                    local item_title = type(item.title) == "string" and item.title or "Unknown"
                    if item_url ~= "" then
                        vim.schedule(function()
                            -- Pre-cache title so the UI shows it immediately
                            state_mod.current.playlist_meta = state_mod.current.playlist_meta or {}
                            state_mod.current.playlist_meta[item_url] = item_title
                            mpv.send_command({ "loadfile", item_url, "append" })
                        end)
                    end
                end
            end
            if pos > 1 then
                partial = partial:sub(pos)
            end
        end
    end)
end

--- Format duration seconds to M:SS or H:MM:SS for long videos
local function fmt_duration(sec)
    if type(sec) ~= "number" or sec <= 0 then
        return ""
    end
    if sec >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60)
    end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--- Truncate string to max width (visual width, not byte count)
local function safe_truncate(str, max_width)
    if not str then
        return ""
    end
    -- Strip newlines and control chars that break nvim_buf_set_lines
    str = str:gsub("[\n\r\t]", " ")
    local visual_width = vim.fn.strdisplaywidth(str)
    if visual_width <= max_width then
        return str
    end
    -- Find truncatable point
    local i = 1
    local width = 0
    while i <= #str do
        local c = str:sub(i, i)
        width = width + (c == "\t" and 8 or vim.fn.strdisplaywidth(c))
        if width > max_width - 3 then
            return str:sub(1, i - 1) .. "..."
        end
        i = i + 1
    end
    return str
end

--- Pad string to right to achieve target visual width
local function pad_right(str, target_width)
    if not str then
        str = ""
    end
    local current = vim.fn.strdisplaywidth(str)
    if current >= target_width then
        return str
    end
    return str .. string.rep(" ", target_width - current)
end

--- Open an interactive search window
---@param initial_query string|nil
function M.interactive_picker(initial_query)
    local buf = vim.api.nvim_create_buf(false, true)

    local width = math.floor(vim.o.columns * 0.75)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
    local col = math.max(0, math.floor((vim.o.columns - width) / 2))

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " ♫ YouTube Search ",
        title_pos = "center",
    })

    -- Lock down all decorations to prevent content bleed-through
    vim.wo[win].cursorline = false
    vim.wo[win].cursorlineopt = "line"
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldcolumn = "0"
    vim.wo[win].wrap = false
    vim.wo[win].winblend = 0
    vim.wo[win].winhighlight = "Normal:NormalFloat"
    if vim.fn.has("nvim-0.9") == 1 then
        vim.wo[win].statuscolumn = ""
    end

    -- Re-measure actual content width after decorations are locked
    width = vim.api.nvim_win_get_width(win)

    -- State
    local current_query = initial_query or ""
    local is_searching = false
    local results = {}
    local current_job = nil
    local spinner_idx = 0
    local selected_idx = 1
    local current_playing_url = nil -- Track URL of currently playing track

    -- Layout constants
    local HEADER_LINES = 2 -- prompt + separator
    local FOOTER_LINE = height

    -- Lines per result card (title + meta + separator)
    local LINES_PER_RESULT = 3

    -- Prompt
    local prompt_prefix = " 🔍 "

    -- Initial buffer setup
    local function render_initial()
        local separator = string.rep("━", width)
        local lines = {
            prompt_prefix .. current_query,
            separator,
            "",
        }
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

        -- Apply highlights
        vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPrompt", 0, 0, #prompt_prefix)
        vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSeparator", 1, 0, -1)
    end

    -- Build footer lines and highlight data
    local function build_footer_lines()
        local badges = {
            { key = "j/k", desc = "Navigate" },
            { key = "↵",   desc = "Play" },
            { key = "a",   desc = "Queue" },
            { key = "i",   desc = "Search" },
            { key = "q",   desc = "Close" },
        }
        local parts = {}
        for _, b in ipairs(badges) do
            table.insert(parts, string.format(" %s %s ", b.key, b.desc))
        end
        local help_text = "  " .. table.concat(parts, "  │  ")
        local sep = string.rep("─", width)
        return { sep, help_text }, badges
    end

    -- Render footer at the bottom of the buffer (used for initial empty state)
    local function render_footer()
        local footer_lines, badges = build_footer_lines()
        vim.bo[buf].modifiable = true
        local line_count = vim.api.nvim_buf_line_count(buf)
        vim.api.nvim_buf_set_lines(buf, line_count, -1, false, footer_lines)
        local sep_line = line_count
        local help_line = line_count + 1
        vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSeparator", sep_line, 0, -1)
        vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchFooter", help_line, 0, -1)
        local offset = 2
        for _, b in ipairs(badges) do
            local badge_str = string.format(" %s %s ", b.key, b.desc)
            local key_str = " " .. b.key
            vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchHotkey", help_line, offset, offset + #key_str)
            offset = offset + #badge_str + 5
        end
        vim.bo[buf].modifiable = false
    end

    -- Render loading state with spinner
    local function render_loading(query)
        -- Don't render if not searching anymore
        if not is_searching then
            return
        end
        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end

        local spinners = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
        spinner_idx = (spinner_idx % #spinners) + 1
        local spinner = spinners[spinner_idx]

        local text = string.format(" %s Searching for '%s'...", spinner, query or "...")
        local line_count = vim.api.nvim_buf_line_count(buf)

        -- Clear results area and show loading
        vim.bo[buf].modifiable = true
        if line_count > HEADER_LINES then
            vim.api.nvim_buf_set_lines(buf, HEADER_LINES, -1, false, {})
        end
        vim.api.nvim_buf_set_lines(buf, HEADER_LINES, HEADER_LINES + 1, false, { text })
        vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchLoading", HEADER_LINES, 0, -1)
        vim.bo[buf].modifiable = false

        -- Schedule next frame
        if is_searching then
            vim.defer_fn(function()
                render_loading(query)
            end, 80)
        end
    end

    -- Render results - premium card layout
    local function render_results()
        if not vim.api.nvim_buf_is_valid(buf) then
            return
        end
        if #results == 0 then
            return
        end

        local display = {}

        for i, r in ipairs(results) do
            local is_selected = (i == selected_idx)
            local is_playing = (r.url == current_playing_url)

            -- Format duration
            local dur = fmt_duration(r.duration)

            -- Left accent: selected gets a bar, playing gets play icon, rest get space
            local accent = is_playing and " ▶" or (is_selected and " ▎" or "  ")

            -- Index: zero-padded for alignment
            local idx_str = string.format("%2d", i)

            -- Calculate available title width
            local prefix_width = vim.fn.strdisplaywidth(accent) + 1 + vim.fn.strdisplaywidth(idx_str) + 2 -- " idx. "
            local title_max = width - prefix_width - 1

            -- Build title line: " ▎  1. Title Here"
            local title_text = safe_truncate(r.title, title_max)
            local title_line = accent .. " " .. idx_str .. ". " .. title_text

            -- Meta line: channel · duration (side by side)
            local indent = string.rep(" ", vim.fn.strdisplaywidth(accent) + 1 + vim.fn.strdisplaywidth(idx_str) + 2)
            local channel = r.channel and r.channel ~= "" and (r.channel:gsub("[\n\r]", " ")) or ""

            local meta_parts = {}
            if channel ~= "" then
                table.insert(meta_parts, channel)
            end
            if dur ~= "" then
                table.insert(meta_parts, dur)
            end
            if is_playing then
                table.insert(meta_parts, "♫ Now Playing")
            end

            local meta_line = indent .. table.concat(meta_parts, "  ·  ")

            -- Empty line separator
            local sep_line = ""

            table.insert(display, title_line)
            table.insert(display, meta_line)
            if i < #results then
                table.insert(display, sep_line)
            end
        end

        -- Pad all lines to full window width
        for idx, line in ipairs(display) do
            local lw = vim.fn.strdisplaywidth(line)
            if lw < width then
                display[idx] = line .. string.rep(" ", width - lw)
            end
        end

        -- Append footer
        local footer_lines, badges = build_footer_lines()
        for _, fl in ipairs(footer_lines) do
            local fl_width = vim.fn.strdisplaywidth(fl)
            if fl_width < width then
                fl = fl .. string.rep(" ", width - fl_width)
            end
            table.insert(display, fl)
        end

        -- Write to buffer
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 2, -1, false, display)

        -- Clear old highlights
        vim.api.nvim_buf_clear_namespace(buf, ns, 2, 2 + #display)

        -- Highlight each result card
        for i, r in ipairs(results) do
            local title_ln = 2 + (i - 1) * LINES_PER_RESULT
            local meta_ln = title_ln + 1
            local sep_ln = title_ln + 2
            local is_selected = (i == selected_idx)
            local is_playing = (r.url == current_playing_url)

            local accent_byte_len = is_playing and #" ▶" or (is_selected and #" ▎" or 2)

            if is_playing then
                -- Playing: green accent + green title + green meta
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlaying", title_ln, 0, accent_byte_len)
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlayingTitle", title_ln, accent_byte_len, -1)
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchPlayingMeta", meta_ln, 0, -1)
            elseif is_selected then
                -- Selected: purple accent bar + highlighted bg on both lines
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchAccent", title_ln, 0, accent_byte_len)
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSelectedTitle", title_ln, accent_byte_len, -1)
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchAccent", meta_ln, 0, accent_byte_len)
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSelectedMeta", meta_ln, 0, -1)

                -- Duration portion on meta line
                local meta_content = display[(i - 1) * LINES_PER_RESULT + 2] or ""
                local dur = fmt_duration(r.duration)
                if dur ~= "" then
                    local dur_byte_start = meta_content:find(dur, 1, true)
                    if dur_byte_start then
                        -- Highlighting to the exact end of the duration text
                        vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSelectedDur", meta_ln, dur_byte_start - 1, dur_byte_start - 1 + #dur)
                    end
                end
            else
                -- Normal: dim index, normal title, channel color
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchIndex", title_ln, 0, accent_byte_len + 5)
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchTitle", title_ln, accent_byte_len + 5, -1)
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchChannel", meta_ln, 0, -1)

                -- Duration highlight on meta line
                local meta_content = display[(i - 1) * LINES_PER_RESULT + 2] or ""
                local dur = fmt_duration(r.duration)
                if dur ~= "" then
                    local dur_byte_start = meta_content:find(dur, 1, true)
                    if dur_byte_start then
                        vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchDuration", meta_ln, dur_byte_start - 1, dur_byte_start - 1 + #dur)
                    end
                end
            end

            -- Separator line (dim)
            if i < #results then
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSeparator", sep_ln, 0, -1)
            end
        end

        -- Footer highlights
        local footer_sep_line = 2 + #display - 2
        local footer_help_line = 2 + #display - 1
        vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchSeparator", footer_sep_line, 0, -1)
        vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchFooter", footer_help_line, 0, -1)
        local offset = 2
        for _, b in ipairs(badges) do
            local badge_str = string.format(" %s %s ", b.key, b.desc)
            local key_str = " " .. b.key
            vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchHotkey", footer_help_line, offset, offset + #key_str)
            offset = offset + #badge_str + 5
        end

        vim.bo[buf].modifiable = false
    end

    -- Jump to search input
    local function enter_search_mode()
        vim.bo[buf].modifiable = true
        vim.api.nvim_win_set_cursor(win, { 1, #prompt_prefix })
        vim.cmd("startinsert!")
    end

    -- Perform search
    local function do_search()
        -- Get the raw line from buffer first
        local lines = vim.api.nvim_buf_get_lines(buf, 0, 1, false)
        local line = lines[1] or ""

        -- Extract query after the emoji prefix
        local query = line:gsub("^%s*🔍%s*", "")
        query = vim.trim(query)

        -- Guard: don't search for empty/nil
        if not query or query == "" then
            return
        end

        current_query = query
        is_searching = true
        results = {}
        selected_idx = 1

        -- Start spinner animation
        spinner_idx = 0
        render_loading(query)
        vim.cmd("stopinsert")

        local limit = require("yt-player").config.search.limit or 10

        -- Kill previous job
        if current_job and not current_job:is_closing() then
            pcall(function()
                current_job:kill(15)
            end)
        end

        current_job = M.search(current_query, limit, function(res, err)
            current_job = nil
            is_searching = false

            if not vim.api.nvim_buf_is_valid(buf) then
                return
            end

            if err then
                vim.bo[buf].modifiable = true
                vim.api.nvim_buf_set_lines(buf, HEADER_LINES, -1, false, { "  Error: " .. err })
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchError", HEADER_LINES, 0, -1)
                vim.bo[buf].modifiable = false
                return
            end

            if #res == 0 then
                vim.bo[buf].modifiable = true
                vim.api.nvim_buf_set_lines(buf, HEADER_LINES, -1, false, { "  No results found." })
                vim.api.nvim_buf_add_highlight(buf, ns, "YTSearchEmpty", HEADER_LINES, 0, -1)
                vim.bo[buf].modifiable = false
                return
            end

            results = res
            selected_idx = 1
            render_results()

            -- Jump to first result
            vim.api.nvim_win_set_cursor(win, { HEADER_LINES + 1, 0 })
        end)
    end

    -- Get current result at cursor
    local function get_current_result()
        local r = vim.api.nvim_win_get_cursor(win)[1]
        -- Each result card takes LINES_PER_RESULT lines, offset by count bar + header
        local result_idx = math.floor((r - HEADER_LINES - 1) / LINES_PER_RESULT) + 1
        if result_idx < 1 or result_idx > #results then
            return nil
        end
        return results[result_idx]
    end

    -- Jump to specific result index
    local function jump_to_index(idx)
        if #results == 0 then
            return
        end
        selected_idx = math.max(1, math.min(#results, idx))
        local target_line = HEADER_LINES + 1 + (selected_idx - 1) * LINES_PER_RESULT
        vim.api.nvim_win_set_cursor(win, { target_line, 0 })
        render_results()
    end

    -- Navigation
    local function jump(dir)
        if vim.fn.mode() == "i" then
            vim.cmd("stopinsert")
        end
        if #results == 0 then
            return
        end

        selected_idx = math.max(1, math.min(#results, selected_idx + dir))
        local target_line = HEADER_LINES + 1 + (selected_idx - 1) * LINES_PER_RESULT
        vim.api.nvim_win_set_cursor(win, { target_line, 0 })
        render_results()
    end

    -- Play current result
    local function play_result()
        if vim.fn.mode() == "i" then
            vim.cmd("stopinsert")
        end
        local res = get_current_result()
        if res and res.url ~= "" then
            current_playing_url = res.url -- Track this as playing
            require("yt-player").load(res.url)
            vim.notify("YT Control: Playing -> " .. res.title, vim.log.levels.INFO)
            render_results() -- Update playing indicator
        end
    end

    -- Append to queue
    local function append_result()
        if vim.fn.mode() == "i" then
            vim.cmd("stopinsert")
        end
        local res = get_current_result()
        if res and res.url ~= "" then
            -- Store title metadata
            local state_mod = require("yt-player.state")
            state_mod.current.playlist_meta = state_mod.current.playlist_meta or {}
            state_mod.current.playlist_meta[res.url] = res.title

            local mpv = require("yt-player.mpv")
            if not mpv.is_running() then
                require("yt-player").load(res.url)
                current_playing_url = res.url
            else
                mpv.send_command({ "loadfile", res.url, "append-play" })
                current_playing_url = res.url -- Will be playing soon
            end
            vim.notify("YT Control: Queued -> " .. res.title, vim.log.levels.INFO)
            render_results() -- Update playing indicator
        end
    end

    -- Setup keymaps
    local opts = { buffer = buf, silent = true }

    -- Enter to search (line 1) or play (results)
    vim.keymap.set({ "i", "n" }, "<CR>", function()
        local r = vim.api.nvim_win_get_cursor(win)[1]
        if r == 1 then
            if not is_searching then
                do_search()
            end
        else
            play_result()
        end
    end, opts)

    -- Queue with a/A or C-a
    vim.keymap.set({ "i", "n" }, "<C-a>", function()
        local r = vim.api.nvim_win_get_cursor(win)[1]
        if r > 1 then
            append_result()
        end
    end, opts)
    vim.keymap.set("n", "A", append_result, opts)
    vim.keymap.set("n", "a", append_result, opts)

    -- Navigation
    vim.keymap.set("n", "j", function()
        jump(1)
    end, opts)
    vim.keymap.set("n", "k", function()
        jump(-1)
    end, opts)
    vim.keymap.set({ "n", "i" }, "<Down>", function()
        jump(1)
    end, opts)
    vim.keymap.set({ "n", "i" }, "<Up>", function()
        jump(-1)
    end, opts)
    vim.keymap.set("n", "<Tab>", function()
        jump(1)
    end, opts)
    vim.keymap.set("n", "<S-Tab>", function()
        jump(-1)
    end, opts)
    vim.keymap.set("i", "<Tab>", function()
        vim.cmd("stopinsert")
        jump(1)
    end, opts)

    -- First/last
    vim.keymap.set("n", "g", function()
        jump_to_index(#results)
    end, opts) -- last
    vim.keymap.set("n", "G", function()
        jump_to_index(1)
    end, opts) -- first

    -- Alternative navigation in insert mode
    vim.keymap.set("i", "<C-j>", function()
        jump(1)
    end, opts)
    vim.keymap.set("i", "<C-k>", function()
        jump(-1)
    end, opts)

    -- Close
    vim.keymap.set("n", "q", function()
        is_searching = false
        vim.api.nvim_win_close(win, true)
    end, opts)

    -- Prevent editing the prompt prefix
    local function lock_prompt()
        local cursor = vim.api.nvim_win_get_cursor(win)
        if cursor[1] == 1 and cursor[2] < #prompt_prefix then
            vim.api.nvim_win_set_cursor(win, { 1, #prompt_prefix })
        end
    end

    vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
        buffer = buf,
        callback = lock_prompt,
    })

    vim.keymap.set("i", "<BS>", function()
        local cursor = vim.api.nvim_win_get_cursor(win)
        if cursor[1] == 1 and cursor[2] <= #prompt_prefix then
            return ""
        end
        return "<BS>"
    end, { buffer = buf, expr = true })

    vim.keymap.set("i", "<C-u>", function()
        local cursor = vim.api.nvim_win_get_cursor(win)
        if cursor[1] == 1 and cursor[2] > #prompt_prefix then
            return string.rep("<BS>", cursor[2] - #prompt_prefix)
        elseif cursor[1] == 1 then
            return ""
        end
        return "<C-u>"
    end, { buffer = buf, expr = true })

    vim.keymap.set("i", "<C-w>", function()
        local cursor = vim.api.nvim_win_get_cursor(win)
        if cursor[1] == 1 and cursor[2] <= #prompt_prefix then
            return ""
        end
        return "<C-w>"
    end, { buffer = buf, expr = true })

    vim.keymap.set("i", "<Left>", function()
        local cursor = vim.api.nvim_win_get_cursor(win)
        if cursor[1] == 1 and cursor[2] <= #prompt_prefix then
            return ""
        end
        return "<Left>"
    end, { buffer = buf, expr = true })

    -- Search (new query) - press i to edit search
    vim.keymap.set("n", "i", enter_search_mode, opts)

    -- Escape: close if on first line, otherwise go to search
    vim.keymap.set("n", "<Esc>", function()
        local r = vim.api.nvim_win_get_cursor(win)[1]
        if r == 1 then
            is_searching = false
            vim.api.nvim_win_close(win, true)
        else
            enter_search_mode()
        end
    end, opts)

    -- Initialize UI
    render_initial()
    render_footer()

    if initial_query and initial_query ~= "" then
        do_search()
    else
        vim.bo[buf].modifiable = true
        vim.api.nvim_win_set_cursor(win, { 1, #prompt_prefix })
        vim.cmd("startinsert!")
    end

    -- Cleanup on close
    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = buf,
        once = true,
        callback = function()
            is_searching = false
            if current_job and not current_job:is_closing() then
                pcall(function()
                    current_job:kill(15)
                end)
            end
        end,
    })
end

return M
