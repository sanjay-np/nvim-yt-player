---@mod yt-player.commands User commands
local M = {}

function M.setup(config)
  M.config = config
  M._register()
end

function M._register()
  local yt = function() return require("yt-player") end

  local subcommands = {
    play = {
      impl = function(args)
        if args and args ~= "" then
          yt().load(args)
        else
          yt().command({ "set_property", "pause", false })
        end
      end,
      desc = "Play URL/search or resume",
      nargs = "?"
    },
    pause = {
      impl = function() yt().command({ "set_property", "pause", true }) end,
      desc = "Pause playback",
    },
    toggle = {
      impl = function() yt().command({ "cycle", "pause" }) end,
      desc = "Toggle play/pause",
    },
    stop = {
      impl = function() yt().command({ "stop" }) end,
      desc = "Stop playback",
    },
    next = {
      impl = function() yt().command({ "playlist-next", "weak" }) end,
      desc = "Next track",
    },
    prev = {
      impl = function() yt().command({ "playlist-prev", "weak" }) end,
      desc = "Previous track",
    },
    mute = {
      impl = function() yt().command({ "cycle", "mute" }) end,
      desc = "Toggle mute",
    },
    seek = {
      impl = function(args)
        local s = tonumber(args)
        if s then
          yt().command({ "seek", s, "absolute" })
        else
          vim.notify("YT Control: Invalid seconds", vim.log.levels.ERROR)
        end
      end,
      desc = "Seek to position (seconds)",
      nargs = 1
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
      nargs = 1
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
      nargs = 1
    },
    vol_up = {
      impl = function() yt().command({ "add", "volume", 5 }) end,
      desc = "Volume +5",
    },
    vol_down = {
      impl = function() yt().command({ "add", "volume", -5 }) end,
      desc = "Volume -5",
    },
    speed = {
      impl = function(args)
        local r = tonumber(args)
        if r and r >= 0.25 and r <= 3 then
          yt().command({ "set_property", "speed", r })
        else
          vim.notify("YT Control: Speed must be 0.25 - 3.0", vim.log.levels.ERROR)
        end
      end,
      desc = "Set speed (0.25-3.0)",
      nargs = 1
    },
    speed_up = {
      impl = function() yt().command({ "add", "speed", 0.25 }) end,
      desc = "Speed +0.25",
    },
    speed_down = {
      impl = function() yt().command({ "add", "speed", -0.25 }) end,
      desc = "Speed -0.25",
    },
    shuffle = {
      impl = function() yt().command({ "playlist-shuffle" }) end,
      desc = "Shuffle playlist",
    },
    repeat_toggle = {
      impl = function() yt().command({ "cycle-values", "loop-playlist", "yes", "no" }) end,
      desc = "Toggle repeat",
    },
    info = {
      impl = function() require("yt-player.player").toggle_float() end,
      desc = "Toggle floating player window",
    },
    ui = {
      impl = function() require("yt-player.player").toggle_panel() end,
      desc = "Toggle player side-panel",
    },
    player = {
      impl = function() require("yt-player.player").toggle_panel() end,
      desc = "Toggle player side-panel",
    },
    search = {
      impl = function(args)
        require("yt-player.search").interactive_picker(args)
      end,
      desc = "Search YouTube",
      nargs = "?"
    },
    queue = {
      impl = function(args)
        if not args or args == "" then
          vim.notify("YT Control: Provide a URL to queue", vim.log.levels.ERROR)
          return
        end
        local mpv = require("yt-player.mpv")
        if not mpv.is_running() then
          yt().load(args)
        else
          mpv.send_command({ "loadfile", args, "append-play" })
          vim.notify("YT Control: Queued", vim.log.levels.INFO)
        end
      end,
      desc = "Queue a URL to the playlist",
      nargs = 1
    },
    queue_edit = {
      impl = function() require("yt-player.queue").open() end,
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
      nargs = 1
    }
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

    subcmd.impl(subcmd_args)
  end, {
    desc = "YT Control Master Command",
    nargs = "*",
    complete = function(ArgLead, CmdLine, CursorPos)
      -- Simple autocomplete for subcommands
      local matches = {}
      for name, _ in pairs(subcommands) do
        if name:lower():match("^" .. ArgLead:lower()) then
          table.insert(matches, name)
        end
      end
      table.sort(matches)
      return matches
    end
  })
end

return M
