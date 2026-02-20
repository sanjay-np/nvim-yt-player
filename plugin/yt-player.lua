-- plugin/yt-player.lua
-- Marks the plugin as loaded to prevent duplicate loads.
-- Setup must be explicitly called by the user via require('yt-player').setup({})

if vim.g.yt_control_loaded then
    return
end

vim.g.yt_control_loaded = true
