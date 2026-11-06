-- Run from the project root:
-- nvim --headless -u NONE -i NONE -n -c 'set rtp+=.' -c 'lua dofile("tests/core_spec.lua")'
-- Offline checks for playback, persistence and radio logic. mpv, yt-dlp and the
-- network are never used; data and cache paths point into a temp directory.
local function run()
	local root = vim.fn.tempname()
	vim.fn.stdpath = function(what)
		local dir = root .. "/" .. what
		vim.fn.mkdir(dir, "p")
		return dir
	end
	local notes = {}
	vim.notify = function(msg)
		table.insert(notes, msg)
	end

	local checks = 0
	local function check(condition, message)
		checks = checks + 1
		assert(condition, message)
	end

	local yt = require("yt-player")
	-- Statusline components (lualine) may render before setup() has run.
	check(pcall(yt.is_connected) and pcall(yt.statusline), "Statusline helpers throw before setup()")
	yt.setup({})
	local mpv = require("yt-player.mpv")
	local state = require("yt-player.state")
	local utils = require("yt-player.utils")
	local radio = require("yt-player.radio")

	-- Unix socket paths are length-limited, so keep this one short.
	mpv.ipc_socket_path = string.format("/tmp/ytp-spec-%d.sock", vim.fn.getpid())

	-- A second Neovim attaches to a running player instead of spawning another.
	do
		-- Any listening socket stands in for mpv here.
		local server = vim.fn.serverstart(mpv.ipc_socket_path)
		local spawned, connects = 0, 0
		local real_jobstart, real_connect = vim.fn.jobstart, mpv._connect_ipc_with_retry
		vim.fn.jobstart = function()
			spawned = spawned + 1
			return 1
		end
		mpv._connect_ipc_with_retry = function()
			connects = connects + 1
		end
		check(mpv.start("https://www.youtube.com/watch?v=aaaaaaaaaaa") == true, "start() failed with a live socket")
		check(spawned == 0, "Spawned a second mpv while one was listening on the socket")
		check(mpv.is_external_client and connects == 1, "Did not attach to the running player")
		mpv.setup(yt.config)
		check(connects == 1, "Re-running setup opened a second IPC connection")
		mpv._cleanup_ipc()
		vim.fn.serverstop(server)
		vim.fn.jobstart, mpv._connect_ipc_with_retry = real_jobstart, real_connect
	end

	-- Stub the transport for everything below.
	local sent = {}
	mpv.is_running = function()
		return true
	end
	mpv.ipc_connected = true
	mpv.send_command = function(command)
		table.insert(sent, command)
		return true
	end

	-- :YT resume reloads the saved queue.
	do
		utils.atomic_write_json(vim.fn.stdpath("data") .. "/yt-player-session.json", {
			playlist = {
				{ filename = "https://www.youtube.com/watch?v=aaaaaaaaaaa" },
				{ filename = "https://www.youtube.com/watch?v=bbbbbbbbbbb" },
			},
			playlist_pos = 1,
		})
		sent, notes = {}, {}
		require("yt-player.session").restore()
		check(
			#sent == 2 and sent[1][3] == "replace" and sent[2][3] == "append",
			"Session restore did not reload the saved queue: " .. vim.inspect(notes)
		)
	end

	-- One track-change notification per track, with the artist, and none for
	-- the placeholder titles shown while loading or after the track ends.
	do
		local url = "https://www.youtube.com/watch?v=ccccccccccc"
		notes = {}
		mpv.load_url(url)
		state.current.artist_map[url] = "Some Artist"
		state.current.playlist, state.current.playlist_pos = { { filename = url } }, 0
		local function title(data)
			mpv._handle_ipc_message(vim.json.encode({ event = "property-change", name = "media-title", data = data }))
		end
		title("watch?v=ccccccccccc")
		title("Real Song")
		mpv._handle_ipc_message(vim.json.encode({ event = "end-file", reason = "eof" }))
		check(
			#notes == 1 and notes[1]:find("Real Song - Some Artist", 1, true) ~= nil,
			"Unexpected track notifications: " .. vim.inspect(notes)
		)
		require("yt-player.notify").track_change("Solo", "")
		check(notes[#notes] == "YT Control: ▶ Solo", "Dangling separator without an artist: " .. notes[#notes])
	end

	-- An unreadable playlists file is backed up rather than overwritten.
	do
		local path = vim.fn.stdpath("data") .. "/yt-player-playlists.json"
		local original = '{"Favs":[{"title":"A","url":"u1"}],}'
		local f = assert(io.open(path, "w"))
		f:write(original)
		f:close()
		require("yt-player.playlists").add_track("New", { title = "B", url = "u2" })
		local backups = vim.fn.glob(path .. ".corrupt-*", false, true)
		check(#backups == 1, "Corrupt playlists file was not backed up")
		local b = assert(io.open(backups[1]))
		check(b:read("*a") == original, "Backup does not hold the original data")
		b:close()
	end

	-- An outdated cached SponsorBlock script is replaced with one that compiles.
	do
		local path = vim.fn.stdpath("cache") .. "/yt_sponsorblock.lua"
		local f = assert(io.open(path, "w"))
		f:write("-- outdated copy")
		f:close()
		check(mpv._ensure_sponsorblock_script() == path, "SponsorBlock script path changed")
		local s = assert(io.open(path))
		local content = s:read("*a")
		s:close()
		check(content ~= "-- outdated copy", "Outdated SponsorBlock script was not replaced")
		check(loadstring(content) ~= nil, "SponsorBlock script does not compile")
	end

	-- Radio only queues recommendations for the track still playing.
	do
		local fetches = {}
		local real_fetch = radio.get_related_tracks
		radio.get_related_tracks = function(video_id, _, callback)
			table.insert(fetches, { id = video_id, callback = callback })
			return nil
		end
		local function play(id)
			state.current.playlist = { { filename = "https://www.youtube.com/watch?v=" .. id } }
			state.current.playlist_pos = 0
		end
		local related = { { title = "R", url = "https://www.youtube.com/watch?v=rrrrrrrrrrr", channel = "" } }
		state.current.radio_enabled, state.current.radio_fetching = true, false
		radio.failed_video_ids = {}

		play("aaaaaaaaaaa")
		radio.check_and_trigger()
		check(#fetches == 1 and fetches[1].id == "aaaaaaaaaaa", "Radio did not fetch for the last track")

		-- The user plays another track before the recommendations arrive.
		play("bbbbbbbbbbb")
		sent = {}
		fetches[1].callback(related, nil)
		check(#sent == 0, "Queued recommendations for a track that is no longer playing")
		check(#fetches == 2 and fetches[2].id == "bbbbbbbbbbb", "Radio did not refetch for the new track")

		fetches[2].callback(related, nil)
		check(#sent == 1 and sent[1][3] == "append-play", "Radio did not queue recommendations: " .. vim.inspect(sent))

		-- Turning radio off mid-fetch drops the late result.
		play("ddddddddddd")
		radio.check_and_trigger()
		radio.toggle()
		sent = {}
		fetches[3].callback(related, nil)
		check(#sent == 0, "Queued recommendations after radio was turned off")
		radio.get_related_tracks = real_fetch
	end

	-- Player windows: no undo history, tabpage-aware, never orphaned.
	do
		local api = vim.api
		local hub = require("yt-player.ui.hub")
		local window = require("yt-player.ui.window")
		hub.open(1)
		check(vim.bo[hub.buf_id].undolevels == -1, "Hub buffer keeps undo history for every redraw")
		vim.cmd("tabnew")
		hub.toggle()
		check(window.is_visible(hub.win_id), "Toggling from another tabpage did not show the hub")
		local file = vim.fn.tempname()
		vim.fn.writefile({ "x" }, file)
		local hub_win = hub.win_id
		pcall(vim.cmd, "edit! " .. vim.fn.fnameescape(file))
		vim.wait(20, function()
			return not api.nvim_win_is_valid(hub_win)
		end)
		check(not api.nvim_win_is_valid(hub_win), "Hub float lingered after its buffer was replaced")
		vim.cmd("silent! %bwipeout! | silent! tabonly!")
	end

	-- The palette follows a theme change but leaves user overrides alone.
	do
		local api = vim.api
		api.nvim_set_hl(0, "YtPlayerArtist", { fg = 0x123456 })
		api.nvim_set_hl(0, "NormalFloat", { bg = 0xffffff })
		local before = api.nvim_get_hl(0, { name = "YtPlayerAccent" }).fg
		api.nvim_exec_autocmds("ColorScheme", {})
		check(api.nvim_get_hl(0, { name = "YtPlayerAccent" }).fg ~= before, "Palette ignored the colorscheme change")
		check(api.nvim_get_hl(0, { name = "YtPlayerArtist" }).fg == 0x123456, "Theme refresh clobbered a user highlight")
	end

	check(utils.format_speed(1.25) == "1.25x" and utils.format_speed(2) == "2x", "Speed formatting drops digits")

	vim.fn.delete(root, "rf")
	print(string.format("Core regression checks passed (%d assertions)", checks))
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
	io.stderr:write(err .. "\n")
	vim.cmd("cquit 1")
else
	vim.cmd("qa!")
end
