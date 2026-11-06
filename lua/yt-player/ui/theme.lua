---@mod yt-player.ui.theme Centralized highlights and icons for yt-player UI
local M = {}

local icons_nerd = {
	play = "󰐊",
	pause = "󰏤",
	prev = "󰒮",
	next = "󰒭",
	volume_high = "󰕾",
	volume_med = "󰖀",
	volume_low = "󰕿",
	volume_mute = "󰝟",
	speed = "󰓅",
	repeat_off = "󰑖",
	repeat_track = "󰑗",
	repeat_all = "󰑖",
	radio = "󰐋",
	music = "󰎆",
	disc = "󰝚",
	search = "󰍉",
	queue = "󰒲",
	playlist = "󰲸",
	history = "󰋚",
	verified = "󰄬",
	artist = "",
	time = "⏱",
	calendar = "📅",
	selected = "▸",
	playing = "󰐊",
	check = "✔",
	cross = "✖",
	bullet = "•",
	folder = "󰉋",
}

local icons_unicode = {
	play = "▶",
	pause = "⏸",
	prev = "⏮",
	next = "⏭",
	volume_high = "♪",
	volume_med = "♪",
	volume_low = "♪",
	volume_mute = "×",
	speed = "»",
	repeat_off = "↻",
	repeat_track = "↻",
	repeat_all = "↻",
	radio = "∿",
	music = "♫",
	disc = "◎",
	search = "⌕",
	queue = "☰",
	playlist = "≡",
	history = "↶",
	verified = "✓",
	artist = "·",
	time = "⏱",
	calendar = "·",
	selected = "▸",
	playing = "▶",
	check = "✓",
	cross = "✗",
	bullet = "•",
	folder = "≡",
}

M.use_nerd_fonts = false

--- Detect if Nerd Fonts should be used
---@param config table|nil
function M.setup(config)
	config = config or {}
	local nf_setting = config.nerd_fonts
	if nf_setting == true then
		M.use_nerd_fonts = true
	elseif nf_setting == false then
		M.use_nerd_fonts = false
	else
		-- Terminal font support cannot be detected reliably; respect the user's hint.
		if vim.g.have_nerd_font ~= nil then
			M.use_nerd_fonts = vim.g.have_nerd_font
		else
			M.use_nerd_fonts = false
		end
	end

	M.setup_highlights(config.theme)

	-- Update highlights dynamically if the colorscheme or background changes
	-- (`:set background=light` on the default colorscheme fires no ColorScheme)
	local augroup = vim.api.nvim_create_augroup("YTPlayerTheme", { clear = true })
	local function refresh()
		M.setup_highlights(config.theme)
	end
	vim.api.nvim_create_autocmd("ColorScheme", { group = augroup, callback = refresh })
	vim.api.nvim_create_autocmd("OptionSet", { group = augroup, pattern = "background", callback = refresh })
end

--- Get icon by name
---@param name string
---@return string
function M.icon(name)
	local tbl = M.use_nerd_fonts and icons_nerd or icons_unicode
	return tbl[name] or ""
end

-- Each group as it read back right after this plugin last set it. On refresh,
-- a group that is empty or still matches is ours to recolor; anything else was
-- customised by the user and is left alone. (`default = true` alone would
-- never recolor a group once set, so the palette could not follow a theme change.)
local applied = {}

--- Setup highlight groups linked to Neovim's standard theme
---@param theme_override string|nil
function M.setup_highlights(theme_override)
	local function def_hl(name, opts)
		-- Leave the terminal/editor background visible on every player surface.
		opts.bg = "NONE"
		opts.ctermbg = "NONE"
		local current = vim.api.nvim_get_hl(0, { name = name })
		if next(current) == nil or vim.deep_equal(current, applied[name]) then
			vim.api.nvim_set_hl(0, name, opts)
			applied[name] = vim.api.nvim_get_hl(0, { name = name })
		end
	end

	local function color(group, key, fallback)
		local ok, value = pcall(vim.api.nvim_get_hl, 0, { name = group, link = false })
		return ok and value[key] or fallback
	end
	local bg = color("NormalFloat", "bg", color("Normal", "bg", 0x141b24))
	local light = ((math.floor(bg / 65536) % 256) + (math.floor(bg / 256) % 256) + bg % 256) > 460
	local function mix(a, b, ratio)
		local result = 0
		for _, power in ipairs({ 65536, 256, 1 }) do
			local channel = math.floor((math.floor(a / power) % 256) * (1 - ratio) + (math.floor(b / power) % 256) * ratio)
			result = result + channel * power
		end
		return result
	end
	bg = mix(bg, light and 0xf2f5fa or 0x111922, light and 0.25 or 0.65)
	local palette = {
		bg = bg,
		panel = mix(bg, light and 0x000000 or 0xffffff, 0.035),
		fg = color("Normal", "fg", light and 0x263445 or 0xd9e2ef),
		muted = light and 0x627084 or 0x8594a8,
		border = light and 0x8c9db1 or 0x60758d,
		accent = light and 0x26795b or 0x8ee3b5,
		cyan = light and 0x237c9c or 0x81cce5,
		amber = light and 0x99641b or 0xecc48d,
	}
	M.palette = palette

	-- Transparent surfaces retain colored text, borders, and selection markers.
	def_hl("YtPlayerNormal", { fg = palette.fg })
	def_hl("YtPlayerPanel", { fg = palette.fg })
	def_hl("YtPlayerBorder", { fg = palette.border })
	def_hl("YtPlayerFrame", { fg = palette.border })
	def_hl("YtPlayerTitle", { fg = palette.accent, bold = true })
	def_hl("YtPlayerFooter", { fg = palette.muted })
	def_hl("YtPlayerBrand", { fg = palette.accent, bold = true })
	def_hl("YtPlayerText", { fg = palette.fg })
	def_hl("YtPlayerMuted", { fg = palette.muted })
	def_hl("YtPlayerAccent", { fg = palette.accent, bold = true })
	def_hl("YtPlayerTitleText", { fg = palette.fg, bold = true })
	def_hl("YtPlayerArtist", { fg = palette.cyan })
	def_hl("YtPlayerActive", { fg = palette.accent, bold = true })
	def_hl("YtPlayerPlaying", { fg = palette.accent, bold = true })
	def_hl("YtPlayerWarning", { fg = palette.amber })
	def_hl("YtPlayerError", { fg = color("DiagnosticError", "fg", light and 0xb02736 or 0xf28b96) })
	def_hl("YtPlayerSelected", { fg = palette.accent, bold = true })
	def_hl("YtPlayerPrefix", { fg = palette.accent, bold = true })
	def_hl("YtPlayerIndex", { fg = palette.muted })
	def_hl("YtPlayerDuration", { fg = palette.cyan })
	def_hl("YtPlayerControl", { fg = palette.fg, bold = true })
	def_hl("YtPlayerRadio", { fg = palette.amber })
	def_hl("YtPlayerVolume", { fg = palette.cyan })
	def_hl("YtPlayerSpeed", { fg = palette.amber })
	def_hl("YtPlayerProgress", { fg = palette.accent, bold = true })
	def_hl("YtPlayerProgressBg", { fg = palette.border })
	def_hl("YtPlayerTabActive", { fg = palette.accent, bold = true, underline = true })
	def_hl("YtPlayerTabInactive", { fg = palette.muted })
	def_hl("YtPlayerBadge", { fg = palette.accent, bold = true })
	def_hl("YtPlayerKeyHint", { fg = palette.cyan })
	def_hl("YtPlayerSeparator", { fg = palette.border })
	def_hl("YtPlayerTransport", { fg = palette.fg })
end

return M
