---@mod yt-player.queue Interactive Queue Management
local M = {}

local state_mod = require("yt-player.state")
local mpv = require("yt-player.mpv")
local utils = require("yt-player.utils")

M.win_id = nil
M.buf_id = nil

local function render_queue()
    if not M.buf_id or not vim.api.nvim_buf_is_valid(M.buf_id) then return end

    local state = state_mod.get_current()
    local plist = state.playlist or {}

    local lines = {
        " 🎵 Interactive Queue ",
        " ──────────────────── ",
        " [Enter] Play    [dd] Remove    [J/K] Move Down/Up    [q/Esc] Close",
        " ",
    }

    if #plist == 0 then
        table.insert(lines, "    (Queue is empty)")
    else
        for i, item in ipairs(plist) do
            local prefix = (i - 1 == state.playlist_pos) and " ▶ " or "   "
            local title = item.title or (state.playlist_meta and state.playlist_meta[item.filename]) or item.filename or
                "Unknown"
            table.insert(lines, string.format("%s%d. %s", prefix, i, title))
        end
    end

    vim.bo[M.buf_id].modifiable = true
    vim.api.nvim_buf_set_lines(M.buf_id, 0, -1, false, lines)
    vim.bo[M.buf_id].modifiable = false
end

function M.open()
    if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
        render_queue()
        vim.api.nvim_set_current_win(M.win_id)
        return
    end

    M.buf_id = vim.api.nvim_create_buf(false, true)

    local width = math.floor(vim.o.columns * 0.6)
    local height = math.floor(vim.o.lines * 0.6)
    local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
    local col = math.max(0, math.floor((vim.o.columns - width) / 2))

    M.win_id = vim.api.nvim_open_win(M.buf_id, true, {
        relative = "editor",
        row = row,
        col = col,
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " YT Queue ",
        title_pos = "center"
    })

    vim.wo[M.win_id].cursorline = true
    vim.bo[M.buf_id].filetype = "yt-player-queue"

    render_queue()

    local opts = { buffer = M.buf_id, silent = true }

    local function get_idx()
        local r = vim.api.nvim_win_get_cursor(M.win_id)[1]
        if r <= 4 then return nil end
        return r - 5 -- 0-indexed for mpv
    end

    local function refresh()
        vim.defer_fn(render_queue, 150)
    end

    -- Play
    vim.keymap.set("n", "<CR>", function()
        local idx = get_idx()
        if idx then mpv.send_command({ "set_property", "playlist-pos", idx }) end
    end, opts)

    -- Remove (dd)
    vim.keymap.set("n", "dd", function()
        local idx = get_idx()
        if idx then
            mpv.send_command({ "playlist-remove", idx })
            refresh()
        end
    end, opts)

    -- Move up (K)
    vim.keymap.set("n", "K", function()
        local idx = get_idx()
        if idx and idx > 0 then
            mpv.send_command({ "playlist-move", idx, idx - 1 })
            vim.api.nvim_win_set_cursor(M.win_id, { vim.api.nvim_win_get_cursor(M.win_id)[1] - 1, 0 })
            refresh()
        end
    end, opts)

    -- Move down (J)
    vim.keymap.set("n", "J", function()
        local idx = get_idx()
        local state = state_mod.get_current()
        if idx and state.playlist and idx < #state.playlist - 1 then
            mpv.send_command({ "playlist-move", idx, idx + 2 })
            vim.api.nvim_win_set_cursor(M.win_id, { vim.api.nvim_win_get_cursor(M.win_id)[1] + 1, 0 })
            refresh()
        end
    end, opts)

    -- Close
    vim.keymap.set("n", "q", function() vim.api.nvim_win_close(M.win_id, true) end, opts)
    vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(M.win_id, true) end, opts)

    -- Auto-refresh on state change isn't strictly needed if we refresh on action,
    -- but an autocmd or simple timer ensures playing pointer stays accurate.
    local timer = vim.loop.new_timer()
    timer:start(1000, 1000, vim.schedule_wrap(function()
        if M.win_id and vim.api.nvim_win_is_valid(M.win_id) then
            render_queue()
        else
            timer:stop()
            timer:close()
        end
    end))

    -- Ensure timer cleanup when buffer is wiped
    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = M.buf_id,
        once = true,
        callback = function()
            if timer and not timer:is_closing() then
                timer:stop()
                timer:close()
            end
            M.win_id = nil
            M.buf_id = nil
        end,
    })
end

return M
