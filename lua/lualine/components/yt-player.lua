-- lualine component for yt-player
-- Usage:
--   require('lualine').setup({
--     sections = {
--       lualine_x = { 'yt-player' }
--     }
--   })

local M = require('lualine.component'):extend()

function M:init(options)
    M.super.init(self, options)
end

function M:update_status()
    local ok, yt = pcall(require, 'yt-player')
    if not ok or not yt.is_connected() then
        return ''
    end
    return yt.statusline()
end

return M
