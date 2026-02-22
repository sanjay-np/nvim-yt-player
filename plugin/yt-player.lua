-- plugin/yt-player.lua
-- Prevents duplicate plugin loads.
-- Setup must be explicitly called by the user via require('yt-player').setup({})

if vim.g.yt_control_loaded then
    return
end
