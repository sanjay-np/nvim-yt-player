---@mod yt-player.search YouTube search via yt-dlp
local M = {}

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

    local stdout_chunks = {}
    local stderr_chunks = {}

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
                stdout:read_stop(); stdout:close()
            end)
        end
        if stderr then
            pcall(function()
                stderr:read_stop(); stderr:close()
            end)
        end
        if handle then pcall(function() handle:close() end) end

        vim.schedule(function()
            if code ~= 0 then
                callback({}, table.concat(stderr_chunks, ""))
                return
            end

            local results = {}
            local raw = table.concat(stdout_chunks, "")

            -- yt-dlp outputs one JSON object per line
            for line in raw:gmatch("[^\n]+") do
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
                        url = type(item.webpage_url) == "string" and item.webpage_url or (type(item.url) == "string" and item.url or ""),
                        id = type(item.id) == "string" and item.id or "",
                        duration = duration,
                        channel = type(item.channel) == "string" and item.channel or (type(item.uploader) == "string" and item.uploader or ""),
                    }
                end
            end

            callback(results, nil)
        end)
    end)

    if not handle then
        if stdout then pcall(function() stdout:close() end) end
        if stderr then pcall(function() stderr:close() end) end
        callback({}, "Failed to spawn yt-dlp")
        return
    end

    stdout:read_start(function(err, data)
        if data then stdout_chunks[#stdout_chunks + 1] = data end
    end)

    stderr:read_start(function(err, data)
        if data then stderr_chunks[#stderr_chunks + 1] = data end
    end)
end

--- Format duration seconds to M:SS
local function fmt_duration(sec)
    if type(sec) ~= "number" or sec <= 0 then return "" end
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

--- Open an interactive search window
---@param initial_query string|nil
function M.interactive_picker(initial_query)
    local buf = vim.api.nvim_create_buf(false, true)

    local width = math.floor(vim.o.columns * 0.7)
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
        title = " 🎵 YouTube Search ",
        title_pos = "center",
    })

    vim.wo[win].cursorline = true

    -- Initialize buffer
    local prompt_prefix = " 🔍 Query: "
    vim.api.nvim_buf_set_lines(buf, 0, -1, false,
        { prompt_prefix .. (initial_query or ""), "", "    Type your query and press Enter..." })

    -- Highlight prompt
    local ns = vim.api.nvim_create_namespace("yt_search")
    vim.api.nvim_buf_add_highlight(buf, ns, "Title", 0, 0, #prompt_prefix)

    local is_searching = false
    local results = {}

    local function render_results()
        if not vim.api.nvim_buf_is_valid(buf) then return end
        local display = {}
        for i, r in ipairs(results) do
            table.insert(display, string.format(" %d. %s", i, r.title))
            table.insert(display, string.format("    📺 %s  ⏱ %s", r.channel, fmt_duration(r.duration)))
            table.insert(display, "")
        end
        if #display > 0 then table.remove(display) end -- remove last spacer

        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 2, -1, false, display)
        vim.bo[buf].modifiable = false
    end

    local function do_search()
        local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
        local query = line:gsub("^%s*🔍 Query:%s*", "")
        query = vim.trim(query)
        if query == "" then return end

        is_searching = true
        results = {}
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 2, -1, false, { "    ⏳ Searching for '" .. query .. "'..." })
        vim.cmd("stopinsert")

        local limit = require("yt-player").config.search.limit or 10
        M.search(query, limit, function(res, err)
            if not vim.api.nvim_buf_is_valid(buf) then return end
            is_searching = false
            if err then
                vim.bo[buf].modifiable = true
                vim.api.nvim_buf_set_lines(buf, 2, -1, false, { "    ❌ Error: " .. err })
                vim.bo[buf].modifiable = false
                return
            end

            if #res == 0 then
                vim.bo[buf].modifiable = true
                vim.api.nvim_buf_set_lines(buf, 2, -1, false, { "    ❌ No results found." })
                vim.bo[buf].modifiable = false
                return
            end

            results = res
            render_results()
            vim.api.nvim_win_set_cursor(win, { 3, 0 })
        end)
    end

    local opts = { buffer = buf, silent = true }

    local function get_current_result()
        local r = vim.api.nvim_win_get_cursor(win)[1]
        if r < 3 or #results == 0 then return nil end
        local idx = math.floor((r - 3) / 3) + 1
        return results[idx]
    end

    local function play_result()
        if vim.fn.mode() == "i" then vim.cmd("stopinsert") end
        local res = get_current_result()
        if res and res.url ~= "" then
            vim.api.nvim_win_close(win, true)
            require("yt-player").load(res.url)
        end
    end

    local function append_result()
        if vim.fn.mode() == "i" then vim.cmd("stopinsert") end
        local res = get_current_result()
        if res and res.url ~= "" then
            -- Store title metadata so player UI can display it before playback starts
            local state_mod = require("yt-player.state")
            state_mod.current.playlist_meta = state_mod.current.playlist_meta or {}
            state_mod.current.playlist_meta[res.url] = res.title

            -- Optional: don't close window instantly on append, let them queue multiple
            local mpv = require("yt-player.mpv")
            if not mpv.is_running() then
                vim.api.nvim_win_close(win, true)
                require("yt-player").load(res.url)
            else
                mpv.send_command({ "loadfile", res.url, "append-play" })
                vim.notify("YT Control: Queued -> " .. res.title, vim.log.levels.INFO)
            end
        end
    end

    vim.keymap.set({ "i", "n" }, "<CR>", function()
        local r = vim.api.nvim_win_get_cursor(win)[1]
        if r == 1 then
            if not is_searching then do_search() end
        else
            play_result()
        end
    end, opts)

    -- <S-CR> is often dropped by terminal emulators, so we provide <C-a>
    vim.keymap.set({ "i", "n" }, "<C-a>", function()
        local r = vim.api.nvim_win_get_cursor(win)[1]
        if r > 1 then append_result() end
    end, opts)

    vim.keymap.set("n", "A", append_result, opts)
    vim.keymap.set("n", "a", append_result, opts)

    local function jump(dir)
        if vim.fn.mode() == "i" then vim.cmd("stopinsert") end
        if #results == 0 then return end
        local r = vim.api.nvim_win_get_cursor(win)[1]
        if r < 3 then
            vim.api.nvim_win_set_cursor(win, { 3, 0 }); return
        end

        local current_idx = math.floor((r - 3) / 3)
        local target_idx = math.max(0, math.min(#results - 1, current_idx + dir))
        vim.api.nvim_win_set_cursor(win, { 3 + (target_idx * 3), 0 })
    end

    vim.keymap.set("n", "j", function() jump(1) end, opts)
    vim.keymap.set("n", "k", function() jump(-1) end, opts)
    vim.keymap.set("n", "<Tab>", function() jump(1) end, opts)
    vim.keymap.set("n", "<S-Tab>", function() jump(-1) end, opts)
    vim.keymap.set("i", "<Tab>", function() jump(1) end, opts)

    vim.keymap.set("n", "q", function() vim.api.nvim_win_close(win, true) end, opts)
    vim.keymap.set("n", "<Esc>", function()
        if vim.api.nvim_win_get_cursor(win)[1] == 1 then
            vim.api.nvim_win_close(win, true)
        else
            vim.api.nvim_win_set_cursor(win, { 1, #prompt_prefix })
            vim.cmd("startinsert!")
        end
    end, opts)

    if initial_query and initial_query ~= "" then
        do_search()
    else
        vim.api.nvim_win_set_cursor(win, { 1, #prompt_prefix })
        vim.cmd("startinsert!")
    end
end

return M
