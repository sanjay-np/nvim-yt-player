---@mod yt-player.playlists Persistent local playlists
local M = {}

local function get_path()
    return vim.fn.stdpath("data") .. "/yt-player-playlists.json"
end

--- Read all playlists
---@return table { [playlist_name] = { {title, url, duration}, ... } }
function M.get_all()
    local f = io.open(get_path(), "r")
    if not f then return {} end
    local content = f:read("*a")
    f:close()
    if content == "" then return {} end
    local ok, data = pcall(vim.json.decode, content)
    if not ok or type(data) ~= "table" then return {} end
    return data
end

--- Write playlists to disk
local function save(data)
    local f = io.open(get_path(), "w")
    if f then
        f:write(vim.json.encode(data))
        f:close()
    end
end

--- Save a track to a playlist
---@param playlist_name string
---@param track table
function M.add_track(playlist_name, track)
    if not track or not track.url or track.url == "" then return end
    if not playlist_name or playlist_name == "" then return end

    local lists = M.get_all()
    if type(lists[playlist_name]) ~= "table" then
        lists[playlist_name] = {}
    end

    -- Check for duplicate URL
    for _, item in ipairs(lists[playlist_name]) do
        if item.url == track.url then
            vim.notify("YT Control: Track already in playlist", vim.log.levels.WARN)
            return
        end
    end

    table.insert(lists[playlist_name], {
        title = track.title or "Unknown",
        url = track.url,
        duration = track.duration or 0,
        added_at = os.time(),
    })

    save(lists)
    vim.notify("YT Control: Added to '" .. playlist_name .. "'", vim.log.levels.INFO)
end

--- Remove a track or an entire playlist
function M.remove_something(playlist_name, track_url)
    local lists = M.get_all()
    if not lists[playlist_name] then return false end

    if track_url then
        local found = false
        local filtered = {}
        for _, item in ipairs(lists[playlist_name]) do
            if item.url == track_url then
                found = true
            else
                table.insert(filtered, item)
            end
        end
        lists[playlist_name] = filtered
        if found then
            save(lists)
            return true
        end
    else
        -- Remove the whole playlist
        lists[playlist_name] = nil
        save(lists)
        return true
    end
    return false
end

--- Helper to prompt selecting/creating a playlist to save a track
function M.prompt_save(track)
    if not track or not track.url or track.url == "" then
        vim.notify("YT Control: Invalid track to save", vim.log.levels.ERROR)
        return
    end

    local lists = M.get_all()
    local list_names = vim.tbl_keys(lists)
    table.sort(list_names)
    table.insert(list_names, 1, "[Create New Playlist]")

    vim.ui.select(list_names, {
        prompt = "Save to Playlist:",
    }, function(choice)
        if not choice then return end

        if choice == "[Create New Playlist]" then
            vim.schedule(function()
                vim.ui.input({ prompt = "New Playlist Name: " }, function(input)
                    if input and vim.trim(input) ~= "" then
                        M.add_track(vim.trim(input), track)
                    end
                end)
            end)
        else
            M.add_track(choice, track)
        end
    end)
end

--- Format duration seconds to M:SS
local function fmt_duration(sec)
    if type(sec) ~= "number" or sec <= 0 then return "0:00" end
    if sec >= 3600 then
        return string.format("%d:%02d:%02d", math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60)
    end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--- Open split-window Playlist Manager
function M.open_manager()
    local lists = M.get_all()
    local list_names = vim.tbl_keys(lists)
    table.sort(list_names)

    local total_w = math.floor(vim.o.columns * 0.8)
    local left_w = math.max(25, math.floor(total_w * 0.3))
    local right_w = total_w - left_w - 2
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
    local col = math.max(0, math.floor((vim.o.columns - total_w) / 2))

    local left_buf = vim.api.nvim_create_buf(false, true)
    local right_buf = vim.api.nvim_create_buf(false, true)

    local left_win = vim.api.nvim_open_win(left_buf, true, {
        relative = "editor",
        row = row,
        col = col,
        width = left_w,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Playlists ",
        title_pos = "center",
    })

    local right_win = vim.api.nvim_open_win(right_buf, false, {
        relative = "editor",
        row = row,
        col = col + left_w + 2,
        width = right_w,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Tracks ",
        title_pos = "center",
    })

    vim.wo[left_win].cursorline = true
    vim.wo[right_win].cursorline = true

    -- Setup highlights
    local ns = vim.api.nvim_create_namespace("yt_playlists")
    vim.api.nvim_set_hl(0, "YTPlaylistHeader", { link = "Title" })
    vim.api.nvim_set_hl(0, "YTPlaylistMeta", { link = "Comment" })

    -- State
    local selected_playlist_idx = 1
    local selected_track_idx = 1
    local current_pane = "left" -- "left" or "right"

    local function get_current_playlist_name()
        if #list_names == 0 then return nil end
        return list_names[selected_playlist_idx]
    end

    local function get_current_tracks()
        local name = get_current_playlist_name()
        if not name then return {} end
        return lists[name] or {}
    end

    -- Render Left Pane
    local function render_left()
        local lines = {}
        if #list_names == 0 then
            table.insert(lines, " (No Playlists)")
        else
            for i, name in ipairs(list_names) do
                local t_count = #(lists[name] or {})
                table.insert(lines, string.format(" %s (%d)", name, t_count))
            end
        end

        local help_lines = {
            string.rep("─", left_w),
            " ↵/l: Open   p: Play",
            " a: Queue   dd: Delete",
            " q: Close"
        }
        while #lines < height - #help_lines do table.insert(lines, "") end
        for _, hl in ipairs(help_lines) do table.insert(lines, hl) end

        vim.bo[left_buf].modifiable = true
        vim.api.nvim_buf_set_lines(left_buf, 0, -1, false, lines)
        vim.bo[left_buf].modifiable = false
        pcall(vim.api.nvim_win_set_cursor, left_win, { math.max(1, selected_playlist_idx), 0 })

        vim.api.nvim_buf_clear_namespace(left_buf, ns, 0, -1)
        local start_hl = #lines - #help_lines
        for i = start_hl, #lines - 1 do
            vim.api.nvim_buf_add_highlight(left_buf, ns, "YTPlaylistMeta", i, 0, -1)
        end
    end

    -- Render Right Pane
    local function render_right()
        local tracks = get_current_tracks()
        local lines = {}
        if #tracks == 0 then
            table.insert(lines, " (No Tracks)")
        else
            for i, t in ipairs(tracks) do
                local title = t.title or "Unknown"
                table.insert(lines, string.format(" %d. %s", i, title))
                table.insert(lines, string.format("    ⏱ %s", fmt_duration(t.duration)))
                table.insert(lines, "")
            end
            if #lines > 0 and lines[#lines] == "" then
                table.remove(lines)
            end
        end

        local help_lines = {
            string.rep("─", right_w),
            " ↵: Play     a: Queue     dd: Delete     h: Back     q: Close"
        }
        while #lines < height - #help_lines do table.insert(lines, "") end
        for _, hl in ipairs(help_lines) do table.insert(lines, hl) end

        vim.bo[right_buf].modifiable = true
        vim.api.nvim_buf_set_lines(right_buf, 0, -1, false, lines)
        vim.bo[right_buf].modifiable = false

        -- Highlight metadata
        vim.api.nvim_buf_clear_namespace(right_buf, ns, 0, -1)
        for i = 1, #tracks do
            local meta_line = (i - 1) * 3 + 1
            if meta_line < #lines - #help_lines then
                vim.api.nvim_buf_add_highlight(right_buf, ns, "YTPlaylistMeta", meta_line, 0, -1)
            end
        end
        local start_hl = #lines - #help_lines
        for i = start_hl, #lines - 1 do
            vim.api.nvim_buf_add_highlight(right_buf, ns, "YTPlaylistMeta", i, 0, -1)
        end

        pcall(vim.api.nvim_win_set_cursor, right_win, { 1, 0 })
    end

    local function focus_pane(pane)
        current_pane = pane
        if pane == "left" then
            vim.api.nvim_set_current_win(left_win)
            vim.wo[left_win].cursorline = true
            vim.wo[right_win].cursorline = false
        else
            if #(get_current_tracks()) > 0 then
                vim.api.nvim_set_current_win(right_win)
                vim.wo[left_win].cursorline = false
                vim.wo[right_win].cursorline = true
            else
                vim.notify("YT Control: No tracks to focus", vim.log.levels.WARN)
                focus_pane("left")
            end
        end
    end

    -- Close helper
    local function close_all()
        pcall(vim.api.nvim_win_close, left_win, true)
        pcall(vim.api.nvim_win_close, right_win, true)
    end

    -- Left Pane Keymaps
    local left_opts = { buffer = left_buf, silent = true }
    vim.keymap.set("n", "q", close_all, left_opts)
    vim.keymap.set("n", "<Esc>", close_all, left_opts)
    
    vim.keymap.set("n", "j", function()
        if selected_playlist_idx < #list_names then
            selected_playlist_idx = selected_playlist_idx + 1
            render_left()
            render_right()
        end
    end, left_opts)
    
    vim.keymap.set("n", "k", function()
        if selected_playlist_idx > 1 then
            selected_playlist_idx = selected_playlist_idx - 1
            render_left()
            render_right()
        end
    end, left_opts)
    
    -- Right/Enter switches to right pane
    vim.keymap.set("n", "l", function() focus_pane("right") end, left_opts)
    vim.keymap.set("n", "<CR>", function() focus_pane("right") end, left_opts)

    -- Play/Queue entire playlist from left pane
    local function action_left(action_type)
        local pl_name = get_current_playlist_name()
        if not pl_name then return end
        local tracks = get_current_tracks()
        if #tracks == 0 then return end
        
        local mpv = require("yt-player.mpv")
        local state_mod = require("yt-player.state")
        
        for i, t in ipairs(tracks) do
            state_mod.current.playlist_meta = state_mod.current.playlist_meta or {}
            state_mod.current.playlist_meta[t.url] = t.title
            if i == 1 and action_type == "play" then
                require("yt-player").load(t.url)
            else
                if not mpv.is_running() then
                    require("yt-player").load(t.url)
                else
                    mpv.send_command({ "loadfile", t.url, "append" })
                end
            end
        end
        vim.notify("YT Control: Queued playlist '" .. pl_name .. "'", vim.log.levels.INFO)
    end

    vim.keymap.set("n", "p", function() action_left("play") end, left_opts)
    vim.keymap.set("n", "a", function() action_left("queue") end, left_opts)

    -- Delete playlist
    vim.keymap.set("n", "dd", function()
        local pl_name = get_current_playlist_name()
        if not pl_name then return end
        if M.remove_something(pl_name, nil) then
            vim.notify("Deleted playlist " .. pl_name, vim.log.levels.INFO)
            lists = M.get_all()
            list_names = vim.tbl_keys(lists)
            table.sort(list_names)
            selected_playlist_idx = math.min(selected_playlist_idx, math.max(1, #list_names))
            render_left()
            render_right()
        end
    end, left_opts)

    -- Right Pane Keymaps
    local right_opts = { buffer = right_buf, silent = true }
    vim.keymap.set("n", "q", close_all, right_opts)
    vim.keymap.set("n", "<Esc>", close_all, right_opts)
    
    vim.keymap.set("n", "h", function() focus_pane("left") end, right_opts)
    
    local function get_right_idx()
        local r = vim.api.nvim_win_get_cursor(right_win)[1]
        return math.floor((r - 1) / 3) + 1
    end

    local function right_jump(dir)
        local tracks = get_current_tracks()
        if #tracks == 0 then return end
        local curr = get_right_idx()
        local target = math.max(1, math.min(#tracks, curr + dir))
        vim.api.nvim_win_set_cursor(right_win, { (target - 1) * 3 + 1, 0 })
    end

    vim.keymap.set("n", "j", function() right_jump(1) end, right_opts)
    vim.keymap.set("n", "k", function() right_jump(-1) end, right_opts)

    -- Play single track
    vim.keymap.set("n", "<CR>", function()
        local tracks = get_current_tracks()
        local t = tracks[get_right_idx()]
        if t then
            require("yt-player").load(t.url)
            vim.notify("YT Control: Playing → " .. t.title, vim.log.levels.INFO)
        end
    end, right_opts)

    -- Queue single track
    vim.keymap.set("n", "a", function()
        local tracks = get_current_tracks()
        local t = tracks[get_right_idx()]
        if t then
            local mpv = require("yt-player.mpv")
            local state_mod = require("yt-player.state")
            state_mod.current.playlist_meta = state_mod.current.playlist_meta or {}
            state_mod.current.playlist_meta[t.url] = t.title
            
            if not mpv.is_running() then
                require("yt-player").load(t.url)
            else
                mpv.send_command({ "loadfile", t.url, "append-play" })
            end
            vim.notify("YT Control: Queued → " .. t.title, vim.log.levels.INFO)
        end
    end, right_opts)

    -- Delete track
    vim.keymap.set("n", "dd", function()
        local pl_name = get_current_playlist_name()
        local tracks = get_current_tracks()
        local t = tracks[get_right_idx()]
        if pl_name and t then
            if M.remove_something(pl_name, t.url) then
                lists = M.get_all()
                render_left()
                render_right()
            end
        end
    end, right_opts)

    -- Synchronize close
    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = left_buf,
        once = true,
        callback = function()
            pcall(vim.api.nvim_win_close, right_win, true)
        end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = right_buf,
        once = true,
        callback = function()
            pcall(vim.api.nvim_win_close, left_win, true)
        end,
    })

    -- Initialization
    render_left()
    render_right()
    focus_pane("left")
end

return M
