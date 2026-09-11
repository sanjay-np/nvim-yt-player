---@mod yt-player.utils Utility functions
local M = {}

---Format seconds to M:SS or H:MM:SS
---Returns "0:00" for nil or zero values.
---@param seconds number|nil
---@return string
function M.format_time(seconds)
	if not seconds or seconds <= 0 or seconds ~= seconds then
		return "0:00"
	end
	seconds = math.floor(seconds)
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

---Format seconds to M:SS or H:MM:SS.
---Returns "" (empty string) for nil or zero values – useful for hiding
---the duration field when it is unknown (e.g. search results, history).
---@param seconds number|nil
---@return string
function M.format_duration(seconds)
	if type(seconds) ~= "number" or seconds <= 0 then
		return ""
	end
	if seconds >= 3600 then
		return string.format(
			"%d:%02d:%02d",
			math.floor(seconds / 3600),
			math.floor((seconds % 3600) / 60),
			seconds % 60
		)
	end
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

---Truncate a string to `max_width` terminal display columns.
---Strips newlines and control characters first so they never break buffer lines.
---@param str string|nil
---@param max_width number
---@return string
function M.safe_truncate(str, max_width)
	if not str or str == "" or not max_width or max_width <= 0 then
		return ""
	end
	-- Strip control characters that would break nvim_buf_set_lines
	str = str:gsub("[\n\r\t]", " ")
	if vim.fn.strdisplaywidth(str) <= max_width then
		return str
	end

	if max_width <= 3 then
		local sub = vim.fn.strcharpart(str, 0, max_width)
		while vim.fn.strdisplaywidth(sub) > max_width and max_width > 0 do
			max_width = max_width - 1
			sub = vim.fn.strcharpart(str, 0, max_width)
		end
		return sub
	end

	local target = max_width - 3
	local low, high = 1, vim.fn.strchars(str)
	local best = 0
	while low <= high do
		local mid = math.floor((low + high) / 2)
		local sub = vim.fn.strcharpart(str, 0, mid)
		if vim.fn.strdisplaywidth(sub) <= target then
			best = mid
			low = mid + 1
		else
			high = mid - 1
		end
	end
	return vim.fn.strcharpart(str, 0, best) .. "..."
end

---Right-pad `str` with spaces until it reaches `target_width` display columns.
---The string is never truncated; use `safe_truncate` first if needed.
---@param str string|nil
---@param target_width number
---@return string
function M.pad_right(str, target_width)
	str = str or ""
	local current = vim.fn.strdisplaywidth(str)
	if current >= target_width then
		return str
	end
	return str .. string.rep(" ", target_width - current)
end

---Sanitize URL to prevent command injection
---@param url string
---@return string
function M.sanitize_url(url)
	if not url or type(url) ~= "string" then
		return ""
	end
	-- Remove newlines and control characters that could break IPC
	url = url:gsub("[%c\r\n]", "")
	-- Trim whitespace
	url = url:match("^%s*(.-)%s*$") or url
	return url
end

---Ensure the parent directory of a file path exists
---@param filepath string
function M.ensure_dir(filepath)
	if not filepath or filepath == "" then
		return
	end
	local dir = vim.fn.fnamemodify(filepath, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
end

---Atomically write JSON data to file using a temporary file and rename
---@param filepath string
---@param data any
---@return boolean
function M.atomic_write_json(filepath, data)
	if not filepath or filepath == "" then
		return false
	end
	M.ensure_dir(filepath)
	local ok_json, json_str = pcall(vim.json.encode, data)
	if not ok_json then
		return false
	end

	local tmp_path = filepath .. ".tmp." .. vim.fn.getpid() .. "." .. math.random(100000, 999999)
	local f = io.open(tmp_path, "w")
	if not f then
		return false
	end
	local ok_write = pcall(function()
		f:write(json_str)
		f:flush()
		f:close()
	end)
	if not ok_write then
		pcall(os.remove, tmp_path)
		return false
	end

	local ok_rename = os.rename(tmp_path, filepath)
	if not ok_rename then
		local uv = vim.uv or vim.loop
		local ok_uv = pcall(uv.fs_rename, tmp_path, filepath)
		if not ok_uv then
			pcall(os.remove, tmp_path)
			return false
		end
	end
	return true
end

---Safely read JSON data from file
---@param filepath string
---@param default_val any
---@return any data, boolean is_corrupt
function M.read_json_file(filepath, default_val)
	if not filepath or filepath == "" or vim.fn.filereadable(filepath) == 0 then
		return default_val, false
	end
	local f = io.open(filepath, "r")
	if not f then
		return default_val, false
	end
	local content = f:read("*a")
	f:close()
	if not content or content == "" then
		return default_val, false
	end
	local ok, data = pcall(vim.json.decode, content)
	if not ok or type(data) ~= type(default_val) then
		return default_val, true
	end
	return data, false
end

return M

