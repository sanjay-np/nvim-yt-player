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

---Format a playback speed multiplier: 1.25 → "1.25x", 1.5 → "1.5x", 2 → "2x".
---@param speed number|nil
---@return string
function M.format_speed(speed)
	local text = string.format("%.2f", tonumber(speed) or 1):gsub("0+$", ""):gsub("%.$", "")
	return text .. "x"
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
	if not ok or (default_val ~= nil and type(data) ~= type(default_val)) then
		return default_val, true
	end
	return data, false
end

---Read a user data file (history, playlists) that must hold a JSON table.
---An unreadable file is moved aside first, so the next save starts fresh
---instead of silently overwriting whatever the user had in it.
---@param filepath string
---@param label string  Shown in the warning, e.g. "playlists"
---@return table
function M.read_json_store(filepath, label)
	local data, is_corrupt = M.read_json_file(filepath, {})
	if is_corrupt then
		local backup = filepath .. ".corrupt-" .. os.date("%Y%m%d-%H%M%S")
		if os.rename(filepath, backup) then
			vim.notify(
				string.format("YT Control: %s file was unreadable; moved it to %s", label, backup),
				vim.log.levels.WARN
			)
		else
			vim.notify(
				string.format("YT Control: %s file is unreadable and could not be backed up: %s", label, filepath),
				vim.log.levels.ERROR
			)
		end
	end
	return data
end

---Extract YouTube 11-char Video ID from any standard or shortened URL
---@param url string|nil
---@return string|nil
function M.extract_video_id(url)
	if not url or type(url) ~= "string" then
		return nil
	end
	local id = string.match(url, "v=([%w_%-]+)")
		or string.match(url, "youtu%.be/([%w_%-]+)")
		or string.match(url, "embed/([%w_%-]+)")
		or string.match(url, "shorts/([%w_%-]+)")
		or string.match(url, "ytdl://([%w_%-]+)")
	if id and #id == 11 then
		return id
	end
	return nil
end

local title_cache = {}
local resolving_titles = {}

---Resolve a clean, human-readable title for a playlist item or URL
---Eliminates raw YouTube links by checking metadata, history, playlists, or querying yt-dlp in the background
---@param item table|string { title, filename, url }
---@param state table|nil
---@return string title
function M.resolve_title(item, state)
	local raw_title = nil
	local url = nil

	if type(item) == "table" then
		raw_title = item.title
		url = item.filename or item.url
	elseif type(item) == "string" then
		url = item
	end

	-- If raw_title is present and is not a URL, return it
	if raw_title and raw_title ~= ""
		and not raw_title:match("^https?://")
		and not raw_title:match("^ytdl://")
		and not raw_title:match("^watch%?v=") then
		return tostring(raw_title):gsub("[\n\r\t]", " ")
	end

	if not url or url == "" then
		return "Unknown Track"
	end

	-- Check title_cache
	if title_cache[url] then
		return title_cache[url]
	end

	state = state or require("yt-player.state").get_current()

	local function extract_clean_text(val)
		if not val then
			return nil
		end
		local s = val
		if type(val) == "table" then
			s = val.title or val.name
		end
		if type(s) == "string" and s ~= "" and not s:match("^https?://") then
			return s
		end
		return nil
	end

	-- Check state.playlist_meta
	if state and state.playlist_meta and state.playlist_meta[url] then
		local meta_t = extract_clean_text(state.playlist_meta[url])
		if meta_t then
			title_cache[url] = meta_t
			return meta_t
		end
	end

	-- Check by 11-char video ID across metadata, history, and playlists
	local vid_id = M.extract_video_id(url)
	if vid_id then
		if title_cache[vid_id] then
			return title_cache[vid_id]
		end

		if state and state.playlist_meta then
			for k, v in pairs(state.playlist_meta) do
				local clean = extract_clean_text(v)
				if clean and type(k) == "string" and k:find(vid_id, 1, true) then
					title_cache[url] = clean
					title_cache[vid_id] = clean
					return clean
				end
			end
		end

		local ok_h, hist_mod = pcall(require, "yt-player.history")
		if ok_h and hist_mod.get then
			local history = hist_mod.get() or {}
			for _, h in ipairs(history) do
				local clean = extract_clean_text(h.title)
				if clean and h.url and h.url:find(vid_id, 1, true) then
					title_cache[url] = clean
					title_cache[vid_id] = clean
					return clean
				end
			end
		end

		local ok_p, pl_mod = pcall(require, "yt-player.playlists")
		if ok_p and pl_mod.get_all then
			local lists = pl_mod.get_all() or {}
			for _, list in pairs(lists) do
				for _, tr in ipairs(list) do
					local clean = extract_clean_text(tr.title)
					if clean and tr.url and tr.url:find(vid_id, 1, true) then
						title_cache[url] = clean
						title_cache[vid_id] = clean
						return clean
					end
				end
			end
		end

		-- Asynchronously fetch title using yt-dlp if not yet resolving
		if not resolving_titles[vid_id] and vim.fn.executable("yt-dlp") == 1 then
			resolving_titles[vid_id] = true
			local uv = vim.uv or vim.loop
			local stdout = uv.new_pipe(false)
			local args = { "yt-dlp", "--no-warnings", "--skip-download", "--print", "title", "https://www.youtube.com/watch?v=" .. vid_id }
			local handle
			handle = uv.spawn(args[1], {
				args = vim.list_slice(args, 2),
				stdio = { nil, stdout, nil },
			}, function()
				if stdout then pcall(function() stdout:read_stop(); stdout:close() end) end
				if handle then pcall(function() handle:close() end) end
				resolving_titles[vid_id] = nil
			end)
			if handle and stdout then
				local out = ""
				stdout:read_start(function(_, data)
					if data then
						out = out .. data
						local t = vim.trim(out:gsub("[\r\n]", ""))
						if t ~= "" and not t:match("^https?://") then
							title_cache[url] = t
							title_cache[vid_id] = t
							if state and state.playlist_meta then
								state.playlist_meta[url] = t
							end
							vim.schedule(function()
								local ok_hub, hub = pcall(require, "yt-player.ui.hub")
								if ok_hub and hub.win_id and vim.api.nvim_win_is_valid(hub.win_id) then
									hub.refresh()
								end
							end)
						end
					end
				end)
			end
		end

		return "YouTube Track [" .. vid_id .. "]"
	end

	local clean = url:gsub("^https?://[^/]+/", ""):gsub("^watch%?", "")
	return clean ~= "" and clean or url
end

return M

