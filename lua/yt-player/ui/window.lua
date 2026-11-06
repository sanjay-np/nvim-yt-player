---@mod yt-player.ui.window Floating window and buffer helpers
local M = {}

M.ns = vim.api.nvim_create_namespace("yt_player_window")
local positions = {}
local last_lines = {}

--- Leave room for the border and command line, even in a small terminal.
function M.clamp_size(width, height)
	return math.max(1, math.min(math.floor(width), vim.o.columns - 4)),
		math.max(1, math.min(math.floor(height), vim.o.lines - vim.o.cmdheight - 4))
end

--- Calculate window position based on mode
---@param width number
---@param height number
---@param position string|nil  "top_right" | "bottom_right" | "center"
---@return number row, number col
function M.calc_position(width, height, position)
	position = position or "center"
	local total_lines = vim.o.lines - vim.o.cmdheight - 1
	local total_cols = vim.o.columns

	local row, col
	if position == "top_right" then
		row = 1
		col = math.max(0, total_cols - width - 3)
	elseif position == "bottom_right" then
		row = math.max(1, total_lines - height - 2)
		col = math.max(0, total_cols - width - 3)
	else -- center
		row = math.max(0, math.floor((total_lines - height) / 2))
		col = math.max(0, math.floor((total_cols - width) / 2))
	end
	return row, col
end

--- Open a styled floating window
---@param opts table { width: number, height: number, position?: string, border?: string, title?: string, title_pos?: string, footer?: string, footer_pos?: string, enter?: boolean, focusable?: boolean, buf?: number }
---@return table { win: number, buf: number }
function M.open_float(opts)
	opts = opts or {}
	local width = opts.width or math.floor(vim.o.columns * 0.7)
	local height = opts.height or math.floor(vim.o.lines * 0.7)
	width, height = M.clamp_size(width, height)
	local row, col = M.calc_position(width, height, opts.position)

	local buf = opts.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		vim.bo[buf].undolevels = -1
	end

	local win_config = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = opts.border or "rounded",
		focusable = opts.focusable ~= false,
		zindex = opts.zindex or 50,
	}

	if opts.title and opts.title ~= "" then
		win_config.title = require("yt-player.utils").safe_truncate(opts.title, math.max(1, width - 4))
		win_config.title_pos = opts.title_pos or "center"
	end

	if opts.footer and opts.footer ~= "" and vim.fn.has("nvim-0.10") == 1 then
		win_config.footer = require("yt-player.utils").safe_truncate(opts.footer, math.max(1, width - 4))
		win_config.footer_pos = opts.footer_pos or "center"
	end

	local enter = opts.enter ~= false
	local ok, win = pcall(vim.api.nvim_open_win, buf, enter, win_config)
	if not ok then
		-- Older Neovim rejects a title/footer when border = "none"; open without them
		win_config.title, win_config.title_pos = nil, nil
		win_config.footer, win_config.footer_pos = nil, nil
		win = vim.api.nvim_open_win(buf, enter, win_config)
	end
	positions[win] = opts.position or "center"
	-- Keep `:e file` (and pickers) from replacing the player buffer inside the float
	pcall(function()
		vim.wo[win].winfixbuf = true
	end)

	-- Window styling
	local winhl = "Normal:YtPlayerNormal,NormalNC:YtPlayerNormal,NormalFloat:YtPlayerNormal,FloatBorder:YtPlayerBorder,FloatTitle:YtPlayerTitle,FloatFooter:YtPlayerFooter,CursorLine:YtPlayerSelected"
	vim.wo[win].winhighlight = winhl
	vim.wo[win].wrap = false
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	vim.wo[win].foldcolumn = "0"
	vim.wo[win].cursorline = opts.cursorline or false
	vim.wo[win].list = false
	vim.wo[win].spell = false
	vim.wo[win].colorcolumn = ""

	return { win = win, buf = buf }
end

function M.set_footer(win, text)
	if not win or not vim.api.nvim_win_is_valid(win) or vim.fn.has("nvim-0.10") == 0 then return end
	local width = vim.api.nvim_win_get_width(win)
	-- Called from refresh timers; an unsupported footer must not raise every tick
	pcall(vim.api.nvim_win_set_config, win, {
		footer = require("yt-player.utils").safe_truncate(text, math.max(1, width - 4)),
		footer_pos = "center",
	})
end

--- True when `win` is valid and in the current tabpage. Floats belong to a
--- single tabpage, so a valid window can still be invisible to the user.
---@param win number|nil
---@return boolean
function M.is_visible(win)
	return win ~= nil
		and vim.api.nvim_win_is_valid(win)
		and vim.api.nvim_win_get_tabpage(win) == vim.api.nvim_get_current_tabpage()
end

function M.resize(win, width, height, position)
	if not win or not vim.api.nvim_win_is_valid(win) then return end
	width, height = M.clamp_size(width, height)
	local row, col = M.calc_position(width, height, position or positions[win])
	vim.api.nvim_win_set_config(win, { relative = "editor", width = width, height = height, row = row, col = col })
end

--- Close window safely
---@param win number|nil
---@param buf number|nil
function M.safe_close(win, buf)
	M.forget(win, buf)
	if win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
	if buf and vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end

--- Release render state when Neovim is already wiping the buffer.
--- If a float outlives its buffer (it was replaced, e.g. `:e!` or Neovim
--- without 'winfixbuf'), close it so it doesn't linger showing another file.
function M.forget(win, buf)
	if win then positions[win] = nil end
	if buf then last_lines[buf] = nil end
	if win then
		vim.schedule(function()
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= "" then
				pcall(vim.api.nvim_win_close, win, true)
			end
		end)
	end
end

--- Render lines to buffer with optional extmarks and highlights
---@param buf number
---@param lines string[]
---@param highlights table[]|nil list of { line: number, hl: string, col_start?: number, col_end?: number, virt_text?: table, virt_text_pos?: string }
function M.render(buf, lines, highlights)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return
	end

	if not vim.deep_equal(last_lines[buf], lines) then
		-- Timers redraw these buffers several times a second. With undo on, every
		-- redraw piles into one never-closed undo block that grows without bound.
		if vim.bo[buf].undolevels ~= -1 then
			vim.bo[buf].undolevels = -1
		end
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		last_lines[buf] = vim.deepcopy(lines)
	end

	vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)

	if highlights then
		for _, h in ipairs(highlights) do
			if h.virt_text then
				pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, h.line, 0, {
					virt_text = h.virt_text,
					virt_text_pos = h.virt_text_pos or "right_align",
				})
			elseif h.hl then
				pcall(
					vim.api.nvim_buf_add_highlight,
					buf,
					M.ns,
					h.hl,
					h.line,
					h.col_start or 0,
					h.col_end or -1
				)
			end
		end
	end
end

return M
