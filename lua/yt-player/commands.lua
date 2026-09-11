---@mod yt-player.commands User commands
local M = {}

function M.setup(config)
	M.config = config
	M._register()
end

function M._register()
	local yt = function()
		return require("yt-player")
	end

	local function parse_time_str(str)
		if not str or str == "" then
			return nil
		end
		local num = tonumber(str)
		if num then
			return num
		end
		local parts = {}
		for p in string.gmatch(str, "[^:]+") do
			local n = tonumber(p)
			if not n then
				return nil
			end
			table.insert(parts, n)
		end
		if #parts == 2 then
			return parts[1] * 60 + parts[2]
		elseif #parts == 3 then
			return parts[1] * 3600 + parts[2] * 60 + parts[3]
		end
		return nil
	end

	local subcommands = {
		play = {
			impl = function(args)
				args = vim.trim(args or "")
				if args ~= "" then
					if args:match("^https?://") or args:match("^ytdl://") then
						yt().load(args)
					else
						yt().load("ytdl://ytsearch:" .. args)
					end
				else
					if not require("yt-player.mpv").is_running() then
						vim.notify("YT Control: mpv is not running. Play a track/URL first.", vim.log.levels.WARN)
						return
					end
					yt().command({ "set_property", "pause", false })
				end
			end,
			desc = "Play URL/search query or resume",
			nargs = "?",
		},
		pause = {
			impl = function()
				yt().command({ "set_property", "pause", true })
			end,
			desc = "Pause playback",
			require_running = true,
		},
		toggle = {
			impl = function()
				yt().command({ "cycle", "pause" })
			end,
			desc = "Toggle play/pause",
			require_running = true,
		},
		stop = {
			impl = function()
				yt().command({ "stop" })
			end,
			desc = "Stop playback",
			require_running = true,
		},
		next = {
			impl = function()
				yt().command({ "playlist-next", "weak" })
			end,
			desc = "Next track",
			require_running = true,
		},
		prev = {
			impl = function()
				yt().command({ "playlist-prev", "weak" })
			end,
			desc = "Previous track",
			require_running = true,
		},
		mute = {
			impl = function()
				yt().command({ "cycle", "mute" })
			end,
			desc = "Toggle mute",
			require_running = true,
		},
		seek = {
			impl = function(args)
				local s = parse_time_str(vim.trim(args or ""))
				if s then
					yt().command({ "seek", s, "absolute" })
				else
					vim.notify("YT Control: Invalid seconds or MM:SS format", vim.log.levels.ERROR)
				end
			end,
			desc = "Seek to position (seconds or MM:SS)",
			nargs = 1,
			require_running = true,
		},
		seek_rel = {
			impl = function(args)
				local s = tonumber(args)
				if s then
					yt().command({ "seek", s, "relative" })
				else
					vim.notify("YT Control: Invalid seconds", vim.log.levels.ERROR)
				end
			end,
			desc = "Seek relative (+/- seconds)",
			nargs = 1,
			require_running = true,
		},
		volume = {
			impl = function(args)
				local v = tonumber(args)
				if v and v >= 0 and v <= 100 then
					yt().command({ "set_property", "volume", v })
				else
					vim.notify("YT Control: Volume must be 0-100", vim.log.levels.ERROR)
				end
			end,
			desc = "Set volume (0-100)",
			nargs = 1,
			require_running = true,
		},
		vol_up = {
			impl = function()
				yt().command({ "add", "volume", 5 })
			end,
			desc = "Volume +5",
			require_running = true,
		},
		vol_down = {
			impl = function()
				yt().command({ "add", "volume", -5 })
			end,
			desc = "Volume -5",
			require_running = true,
		},
		speed = {
			impl = function(args)
				args = vim.trim(args or "")
				if args == "" then
					-- No arg: show current speed
					local state = require("yt-player.state").get_current()
					vim.notify(string.format("YT Control: Speed %.2gx", state.speed or 1), vim.log.levels.INFO)
					return
				end

				-- Named shortcuts
				if args == "up" then
					yt().command({ "add", "speed", 0.25 })
					return
				end
				if args == "down" then
					yt().command({ "add", "speed", -0.25 })
					return
				end

				-- Relative: +N or -N
				if args:match("^[+-]") then
					local delta = tonumber(args)
					if delta then
						yt().command({ "add", "speed", delta })
					else
						vim.notify("YT Control: Invalid speed delta '" .. args .. "'", vim.log.levels.ERROR)
					end
					return
				end

				-- Absolute: N
				local r = tonumber(args)
				if r and r >= 0.25 and r <= 3 then
					yt().command({ "set_property", "speed", r })
				else
					vim.notify("YT Control: Speed must be 0.25–3.0 (or 'up'/'down'/'+N'/'-N')", vim.log.levels.ERROR)
				end
			end,
			desc = "Set/adjust speed: <N> | up | down | +N | -N",
			nargs = "?",
			require_running = true,
		},
		shuffle = {
			impl = function()
				yt().command({ "playlist-shuffle" })
			end,
			desc = "Shuffle playlist",
			require_running = true,
		},
		repeat_toggle = {
			impl = function()
				local state = require("yt-player.state").get_current()
				-- Determine current state (mpv returns "inf", "yes", false, or "no")
				local is_on = state.loop_playlist and state.loop_playlist ~= "no" and state.loop_playlist ~= false
				yt().command({ "cycle-values", "loop-playlist", "inf", "no" })
				if is_on then
					vim.notify("YT Control: 🔁 Repeat Off", vim.log.levels.INFO)
				else
					vim.notify("YT Control: 🔁 Repeat On", vim.log.levels.INFO)
				end
			end,
			desc = "Toggle repeat playlist",
			require_running = true,
		},
		player = {
			impl = function()
				require("yt-player.player").toggle_panel()
			end,
			desc = "Toggle player side-panel",
		},
		mini = {
			impl = function()
				require("yt-player.player").toggle_float()
			end,
			desc = "Toggle floating player window",
		},
		search = {
			impl = function(args)
				require("yt-player.search").interactive_picker(args)
			end,
			desc = "Search YouTube",
			nargs = "?",
		},
		queue = {
			impl = function(args)
				if not args or args == "" then
					vim.notify("YT Control: Provide a URL to queue", vim.log.levels.ERROR)
					return
				end
				local mpv = require("yt-player.mpv")
				local utils = require("yt-player.utils")
				args = utils.sanitize_url(args)
				if args == "" then
					vim.notify("YT Control: Invalid URL", vim.log.levels.ERROR)
					return
				end
				if not mpv.is_running() then
					yt().load(args)
				else
					mpv.send_command({ "loadfile", args, "append-play" })
					vim.notify("YT Control: Queued", vim.log.levels.INFO)
				end
			end,
			desc = "Queue a URL to the playlist",
			nargs = 1,
		},
		queue_edit = {
			impl = function()
				require("yt-player.queue").open()
			end,
			desc = "Interactive Queue Management",
		},
		queue_playlist = {
			impl = function(args)
				if not args or args == "" then
					vim.notify("YT Control: Provide a playlist URL", vim.log.levels.ERROR)
					return
				end
				require("yt-player.search").fetch_playlist(args)
			end,
			desc = "Queue an entire YouTube Playlist",
			nargs = 1,
		},
		history = {
			impl = function()
				require("yt-player.history").open_picker()
			end,
			desc = "Browse play history",
		},
		history_clear = {
			impl = function()
				require("yt-player.history").clear()
			end,
			desc = "Clear play history",
		},
		playlists = {
			impl = function()
				require("yt-player.playlists").open_manager()
			end,
			desc = "Manage local playlists",
		},
		radio = {
			impl = function(args)
				args = vim.trim(args or ""):lower()
				local state = require("yt-player.state").get_current()
				local radio = require("yt-player.radio")
				if args == "on" then
					if not state.radio_enabled then
						radio.toggle()
					end
				elseif args == "off" then
					if state.radio_enabled then
						radio.toggle()
					end
				else
					radio.toggle()
				end
			end,
			desc = "Toggle autoplay radio mode (toggle | on | off)",
			nargs = "?",
		},
		resume = {
			impl = function()
				require("yt-player.session").restore()
			end,
			desc = "Resume last playback session",
		},
	}

	vim.api.nvim_create_user_command("YT", function(opts)
		local args_str = vim.trim(opts.args or "")

		-- Extract subcommand and its arguments
		local delim = args_str:find(" ")
		local subcmd_name = delim and args_str:sub(1, delim - 1) or args_str
		local subcmd_args = delim and vim.trim(args_str:sub(delim + 1)) or ""

		if subcmd_name == "" then
			vim.notify("YT Control: Requires a subcommand. Type :YT and press Tab to see options.", vim.log.levels.WARN)
			return
		end

		local subcmd = subcommands[subcmd_name]
		if not subcmd then
			vim.notify("YT Control: Unknown command '" .. subcmd_name .. "'", vim.log.levels.ERROR)
			return
		end

		if subcmd.require_running and not require("yt-player.mpv").is_running() then
			vim.notify("YT Control: mpv is not running. Play a track/URL first.", vim.log.levels.WARN)
			return
		end

		subcmd.impl(subcmd_args)
	end, {
		desc = "YT Control Master Command",
		nargs = "*",
		complete = function(ArgLead, CmdLine, CursorPos)
			local before = CmdLine:sub(1, CursorPos):gsub("^%s+", "")
			local parts = {}
			for part in before:gmatch("%S+") do
				table.insert(parts, part)
			end
			local trailing_space = before:match("%s$") ~= nil
			local arg_idx = #parts + (trailing_space and 1 or 0)

			-- If completing the subcommand name (arg_idx <= 2)
			if arg_idx <= 2 then
				local matches = {}
				for name, _ in pairs(subcommands) do
					if vim.startswith(name:lower(), ArgLead:lower()) then
						table.insert(matches, name)
					end
				end
				table.sort(matches)
				return matches
			end

			-- Completing secondary arguments for a subcommand
			local subcmd_name = parts[2]
			local candidates = {}

			if subcmd_name == "speed" then
				candidates = { "up", "down", "0.5", "0.75", "1.0", "1.25", "1.5", "1.75", "2.0" }
			elseif subcmd_name == "radio" then
				candidates = { "toggle", "on", "off" }
			elseif subcmd_name == "volume" then
				candidates = { "0", "25", "50", "75", "100" }
			elseif subcmd_name == "seek_rel" then
				candidates = { "+5", "-5", "+10", "-10", "+30", "-30", "+60", "-60" }
			elseif subcmd_name == "seek" then
				candidates = { "0", "30", "60", "120", "300" }
			elseif subcmd_name == "history" then
				candidates = { "clear" }
			elseif subcmd_name == "playlists" then
				local ok, pl_mod = pcall(require, "yt-player.playlists")
				if ok and pl_mod.get_all then
					local lists = pl_mod.get_all()
					for name, _ in pairs(lists) do
						table.insert(candidates, name)
					end
				end
			end

			local matches = {}
			for _, item in ipairs(candidates) do
				if vim.startswith(item:lower(), ArgLead:lower()) then
					table.insert(matches, item)
				end
			end
			table.sort(matches)
			return matches
		end,
	})
end

return M
