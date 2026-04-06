---@mod yt-player.radio Radio / Autoplay mode
local M = {}

M.enabled = false
M.last_url = nil

--- Toggle radio mode
function M.toggle()
    M.enabled = not M.enabled
    local status = M.enabled and "ON 📻" or "OFF"
    vim.notify("YT Control: Radio mode " .. status, vim.log.levels.INFO)
end

--- Called when the playlist ends. Fetches a related video and auto-queues it.
function M.on_queue_end()
    if not M.enabled then return end
    if not M.last_url or M.last_url == "" then return end

    local mpv = require("yt-player.mpv")
    if not mpv.is_running() then return end

    vim.notify("YT Control: 📻 Finding related track...", vim.log.levels.INFO)

    -- Use yt-dlp to fetch related/recommended videos from the last played URL
    local args = {
        "yt-dlp",
        "--flat-playlist",
        "--dump-json",
        "--no-warnings",
        "--no-download",
        "--default-search", "ytsearch",
        -- Fetch the "up next" / related videos by using YouTube's recommendation
        "ytsearch5:related to " .. M.last_url,
    }

    local stdout = vim.loop.new_pipe(false)
    local handle

    handle = vim.loop.spawn(args[1], {
        args = vim.list_slice(args, 2),
        stdio = { nil, stdout, nil },
    }, function(code)
        if stdout then
            pcall(function()
                stdout:read_stop(); stdout:close()
            end)
        end
        if handle then pcall(function() handle:close() end) end

        vim.schedule(function()
            if code ~= 0 then
                vim.notify("YT Control: 📻 Failed to find related tracks", vim.log.levels.WARN)
                return
            end

            if #results == 0 then
                vim.notify("YT Control: 📻 No related tracks found", vim.log.levels.WARN)
                return
            end

            -- Pick a random result from the top results for variety
            local pick = results[math.random(1, math.min(#results, 3))]

            local state_mod = require("yt-player.state")
            state_mod.current.playlist_meta = state_mod.current.playlist_meta or {}
            state_mod.current.playlist_meta[pick.url] = pick.title

            mpv.send_command({ "loadfile", pick.url, "append-play" })
            M.last_url = pick.url

            vim.notify("YT Control: 📻 Auto-playing → " .. pick.title, vim.log.levels.INFO)
        end)
    end)

    if not handle then
        if stdout then pcall(function() stdout:close() end) end
        return
    end

    local results = {}
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
                    local url = type(item.webpage_url) == "string" and item.webpage_url
                        or (type(item.url) == "string" and item.url or "")
                    local title = type(item.title) == "string" and item.title or "Unknown"

                    -- Skip the track we just played
                    if url ~= "" and url ~= M.last_url then
                        table.insert(results, { url = url, title = title })
                    end
                end
            end
            if pos > 1 then
                partial_stdout = partial_stdout:sub(pos)
            end
        end
    end)
end

return M
