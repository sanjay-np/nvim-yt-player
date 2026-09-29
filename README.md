# 🎵 nvim-yt-player

<div align="center">

[![CI](https://github.com/sanjay-np/nvim-yt-player/actions/workflows/ci.yml/badge.svg)](https://github.com/sanjay-np/nvim-yt-player/actions)
![Neovim](https://img.shields.io/badge/Neovim-0.9%2B-blueviolet?logo=neovim&logoColor=white)
![Lua](https://img.shields.io/badge/Lua-Pure%20LuaJIT-blue?logo=lua&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-green.svg)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)

**A premium, lightweight, asynchronous YouTube music & audio player built directly inside Neovim.**  
*Powered by pure Lua, UNIX domain socket IPC, mpv, and yt-dlp. Zero external servers. Zero editor lag.*

</div>

---

```
╭─────────────────────────────── Now Playing ───────────────────────────────╮
│  ♫  Lofi Hip Hop Radio - Beats to Relax/Study to                          │
│     Lofi Girl                                                             │
│                                                                           │
│            ▄▄████████▄▄               [ 01:42 / 03:30 ]                   │
│          ███ ░░░░░░░░ ███            ━━━━━━━━●━━━━━━━━━━                  │
│          ███ ░░  ◉ ░░ ███                                                 │
│            ▀▀████████▀▀               ▃▅█▇▅▃ ▃▅▇█▇▅▃                      │
│                                                                           │
│  🔊 ▰▰▰▰▰▰▰▱▱▱ 70%   ⚡ 1.0x   🔁 Playlist   📻 Radio: ON                   │
╰───────────────────────────────────────────────────────────────────────────╯
```

---

## 💡 Why nvim-yt-player?

- 🚀 **Save 1.5GB+ RAM**: Stop keeping Chrome or Brave open with YouTube tabs just to listen to study/coding music in the background.
- ⚡ **Zero-Freeze Asynchronous IPC**: Communicates directly with `mpv` over a local UNIX domain socket. Stream extraction and playback never block your editor or drop keystrokes.
- ⏩ **Native SponsorBlock**: Automatically skips sponsor segments, promos, and off-topic music intros so your focus is never broken.
- 📻 **Endless Autoplay Radio**: Automatically queries and queues fresh YouTube Mix recommendations matching your active track before the queue ends.
- 👥 **Multi-Instance Sync**: Launch Neovim across multiple tmux panes or terminals—all instances automatically discover and coordinate playback with the shared background daemon.
- 🎛️ **Zero Dependencies**: Pure Lua + `mpv` + `yt-dlp`. No Python daemons, no Node.js processes, no Electron bloat.

---

## ✨ Features

- **⚡ Zero-Freeze Asynchronous Playback**: Stream fetching and caching run entirely in the background. Neovim remains 100% responsive.
- **🏗️ Zero-Dependency Backend**: Pure Lua talking to a local `mpv` process over a UNIX domain IPC socket. No bloated servers or external daemons needed.
- **🎨 Premium Player Layouts**:
  - `:YT player` — Toggles a dedicated side-panel buffer featuring a beautiful custom ASCII bounding-box, a live bouncing music visualizer, an interactive progress slidebar, and volume/speed tracking.
  - `:YT mini` — Toggles a gorgeous floating window with the same premium visual player layout.
- **🔍 Interactive Search Picker (`:YT search`)**: Query YouTube and pick a result using a beautiful floating picker displaying channel names and track durations.
- **📁 Local Playlists (`:YT playlists`)**: Save tracks instantly with `s` and manage them inside a split-pane local playlist manager.
- **📝 Interactive Queue Editor (`:YT queue_edit`)**: Reorder tracks with `J`/`K` or delete them with `dd` in real-time.
- **🎵 Seamless Playlist Ingestion (`:YT queue_playlist`)**: Rapidly ingest and parse YouTube playlists containing 100+ tracks without blocking the UI.
- **⏩ Auto SponsorBlock**: Automatically skip sponsors, intros, and non-music off-topic segments (enable in config).
- **📻 Autoplay Radio Mode (`:YT radio`)**: Endless recommendation stream (enabled by default). Spawns the YouTube Mix playlist matching your active song, deduplicates against active queue and history, and seamlessly appends fresh tracks before your queue ends.
- **📊 Lualine & Statusline Integration**: Formats playing state, volume, speed, and real-time progress bars smoothly for statuslines.
- **🕐 Persistent Play History (`:YT history`)**: Stores recently played tracks so you can jump back or queue them later.
- **🎨 Currently Playing Track Highlight**: The active track is visually highlighted in green across the queue editor, playlist manager, and history picker.
- **🔔 Customizable Notifications**: Control the format of track-change notifications with placeholders like `{title}`, `{artist}`, and `{icon}`.

---

## 📦 Requirements

Before installing, ensure the following commands are available in your system path:
- **Neovim** 0.9+
- **mpv** (configured with Lua support)
- **yt-dlp**

---

## 🔧 Installation

Install using your favorite package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "sanjay-np/nvim-yt-player",
  dependencies = { "nvim-lualine/lualine.nvim" }, -- optional, for statusline component
  config = function()
    require("yt-player").setup({
      -- your configuration options here (see Configuration section)
    })
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "sanjay-np/nvim-yt-player",
  requires = { "nvim-lualine/lualine.nvim" }, -- optional
  config = function()
    require("yt-player").setup()
  end,
}
```

---

## 🚀 Quick Start

1. Start playing a URL immediately:
   ```vim
   :YT play https://www.youtube.com/watch?v=dQw4w9WgXcQ
   ```
2. Search and select tracks interactively:
   ```vim
   :YT search lofi hip hop
   ```
   *In the search picker window:*
   - `<CR>` (Enter): Play selected track (replaces active playlist)
   - `a` / `A` / `<C-a>`: Append selected track to the active queue
   - `s`: Save selected track to a Local Playlist
   - `gg`: Jump to first result
   - `G`: Jump to last result
   - `i`: Re-enter insert mode to refine your query
   - `q` / `<Esc>`: Close the picker

---

## 📋 Command Reference

All functions are available under the master command `:YT` with rich autocomplete (press `<Tab>`!).

| Subcommand | Description |
|:---|:---|
| `:YT play [url]` | Play a URL/search query, or resume playback |
| `:YT pause` | Pause playback |
| `:YT toggle` | Toggle play/pause |
| `:YT stop` | Stop playback entirely |
| `:YT next` / `:YT prev` | Skip to next or previous track |
| `:YT seek <seconds>` | Seek to an absolute position (e.g. `:YT seek 90` jumps to 1m 30s) |
| `:YT seek_rel <±seconds>` | Seek relatively (e.g. `:YT seek_rel -10` seeks back 10 seconds) |
| `:YT volume <0-100>` | Set playback volume |
| `:YT vol_up` / `:YT vol_down` | Increase/decrease volume by 5% |
| `:YT mute` | Toggle playback mute state |
| `:YT speed [value]` | Adjust speed absolutely or relatively (Forms listed below) |
| `:YT player` | Toggle the premium player side-panel |
| `:YT mini` | Toggle the premium player floating window |
| `:YT search [query]` | Open the interactive search picker |
| `:YT queue <url>` | Append a track to the active queue |
| `:YT queue_playlist <url>` | Parse and append all tracks from a YouTube playlist URL |
| `:YT queue_edit` | Open the interactive queue editor |
| `:YT playlists` | Open the split-pane local playlist manager |
| `:YT radio` | Toggle autoplay radio mode (ON by default) |
| `:YT history` | Open the persistent play history picker |
| `:YT history_clear` | Clear play history |
| `:YT resume` | Resume the last persistent playback session |

### Playback Speed Control Forms
- `:YT speed` — Display current speed in a notification
- `:YT speed 1.25` — Set absolute speed (supports values between `0.25` and `3.0`)
- `:YT speed up` / `down` — Adjust speed by `+0.25` / `-0.25`
- `:YT speed +0.5` / `-0.5` — Adjust speed by a custom offset

---

## 🎛️ Interactive Player Controls

When either the side-panel (`:YT player`) or floating window (`:YT mini`) is focused, you can control playback instantly using the following keymaps:

| Keymap | Action |
|:---:|:---|
| `p` / `s` / `t` | **Play** / **Pause** / **Toggle** |
| `n` / `b` | **Next** / **Previous** track |
| `m` | **Mute** toggle |
| `+` / `-` | **Volume** ±5% |
| `>` / `<` | **Speed** ±0.25x |
| `l` / `h` | **Seek** ±5s (relative) |
| `L` / `H` | **Seek** ±30s (relative) |
| `0` to `9` | **Seek** to absolute percentage (`0%` to `90%` of track) |
| `G` | **Seek** to 100% (ends track) |
| `R` | **Cycle Repeat Mode** (Track 🔂 ➔ Playlist 🔁 ➔ Off) |
| `r` | **Toggle Autoplay Radio Mode** |
| `q` / `<Esc>` | **Close** player window |

---

## ⚙️ Configuration

Override defaults by passing options into `setup()`:

```lua
require("yt-player").setup({
  statusline = {
    enabled = true,
    format = "{icon} {title} - {artist} [{position}/{duration}]",
    icon_playing = "▶",
    icon_paused = "⏸",
    truncate_title = 30,
    progress_width = 10,
  },

  search = {
    limit = 10, -- default number of results returned per search query
  },

  notifications = {
    enabled = true,
    notify_on_track_change = true, -- notify when a new song starts playing
    format = "▶ {title} - {artist}", -- customizable notification format
    icon_playing = "▶", -- icon used in notification format
    icon_paused = "⏸", -- icon used when paused
    timeout = 3000, -- notification timeout in ms
  },

  player = {
    queue_display_limit = 5, -- number of upcoming tracks to show in the player layout
  },

  keymaps = {
    enabled = false, -- set to true to enable global keymaps
    prefix = "<leader>y",
    play = "p",
    pause = "s",
    toggle = "t",
    next = "n",
    prev = "b",
    mute = "m",
    volume_up = "+",
    volume_down = "-",
    seek_forward = "f",
    seek_backward = "r",
    speed_up = ">",
    speed_down = "<",
  },
  
  radio = {
    enabled = true, -- set to false to disable autoplay radio by default
    limit = 5,      -- number of related tracks to fetch at a time
  },
  
  youtube = {
    -- Optional yt-dlp player client override for mpv's ytdl_hook.
    -- Leave empty ("") to let yt-dlp pick its own default clients, which is
    -- the most reliable option. Pinning a client (e.g. "android,tv_simply")
    -- tends to break whenever YouTube changes its player endpoints.
    player_client = "",
  },
  
  sponsorblock = false, -- set to true to automatically skip YouTube sponsor segments
})
```

### Statusline Customization
Use these placeholders to customize your statusline:
- `{icon}` — Play/Pause status icon (`▶` / `⏸`)
- `{title}` — Current track title
- `{artist}` — Channel / Uploader name
- `{position}` — Current playback position (e.g. `2:45`)
- `{duration}` — Total track duration (e.g. `4:10`)
- `{progress}` — Interactive progress bar (e.g. `▓▓▓░░░░░░░`)
- `{volume}` — Volume percentage
- `{speed}` — Speed multiplier (e.g. `1.25x`)
- `{radio}` — Autoplay radio status icon (renders `📻` when enabled)

### Notification Customization
Use these placeholders to customize track-change notifications:
- `{title}` — Current track title
- `{artist}` — Channel / Uploader name
- `{icon}` — Playing icon (default `▶`)

Example configurations:
```lua
-- Minimal notification
format = "{title}"

-- Include artist
format = "▶ {title} - {artist}"

-- With icon placeholder
format = "{icon} Now playing: {title}"
```

### Lualine Integration
Add `yt-player` directly to your lualine configuration sections:
```lua
require("lualine").setup({
  sections = {
    lualine_x = { "yt-player" }
  }
})
```

### Highlight Groups
All highlight groups can be customized to match your colorscheme. Override them in your Neovim config:

```lua
-- Player UI highlights
vim.api.nvim_set_hl(0, "YtPlayerTitle", { fg = "#bd93f9", bold = true })
vim.api.nvim_set_hl(0, "YtPlayerArtist", { fg = "#6272a4" })
vim.api.nvim_set_hl(0, "YtPlayerProgress", { fg = "#50fa7b" })
vim.api.nvim_set_hl(0, "YtPlayerProgressBg", { fg = "#44475a" })
vim.api.nvim_set_hl(0, "YtPlayerControls", { fg = "#8be9fd" })
vim.api.nvim_set_hl(0, "YtPlayerVolume", { fg = "#ffb86c" })
vim.api.nvim_set_hl(0, "YtPlayerVolumeBg", { fg = "#44475a" })
vim.api.nvim_set_hl(0, "YtPlayerRadio", { fg = "#ff79c6" })
vim.api.nvim_set_hl(0, "YtPlayerQueue", { fg = "#f8f8f2" })
vim.api.nvim_set_hl(0, "YtPlayerQueueCurrent", { fg = "#50fa7b", bold = true })
vim.api.nvim_set_hl(0, "YtPlayerBorder", { fg = "#6272a4" })
vim.api.nvim_set_hl(0, "YtPlayerHelp", { fg = "#6272a4" })

-- Currently playing track highlights (green by default)
vim.api.nvim_set_hl(0, "YTQueueCurrent", { fg = "#50fa7b", bold = true })
vim.api.nvim_set_hl(0, "YTPlaylistCurrent", { fg = "#50fa7b", bold = true })
vim.api.nvim_set_hl(0, "YTHistoryCurrent", { fg = "#50fa7b", bold = true })
```

---

## 🏗️ Architecture

```
Neovim (Lua) ── UNIX Socket ──➔ mpv ──➔ yt-dlp ──➔ YouTube Stream
```

The plugin spawns a headless, detached background `mpv` process with IPC enabled. Multiple Neovim instances safely share the same `mpv` process via standard client process registration. The socket is automatically cleaned up when the last client closes.

---

## 🔧 Troubleshooting

- **Tracks skip instantly with no audio?** This is usually one of two things:
  1. **A pinned yt-dlp player client that YouTube no longer supports.** Pinning a client such as `android,tv_simply` can make yt-dlp return no usable formats, so every track fails instantly. The plugin no longer pins one by default; if you set `youtube.player_client`, clear it:
     ```lua
     require("yt-player").setup({
       youtube = { player_client = "" }, -- let yt-dlp choose
     })
     ```
  2. **Browser cookies forwarded to yt-dlp by your mpv config.** If your `mpv.conf` contains
     ```
     ytdl-raw-options-add=cookies-from-browser=brave
     ```
     yt-dlp resolves streams through a cookie-authenticated client, and the resulting `googlevideo.com` URLs are rejected with `HTTP 403` when mpv/ffmpeg fetches them (even though `yt-dlp` can download the same URL). Remove that line unless you specifically need signed-in content.
- **No Audio?** Check that both `mpv` and `yt-dlp` are functioning correctly on your system by playing a URL directly:
  ```bash
  mpv --no-video "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  ```
- **Outdated yt-dlp?** If YouTube streams fail to parse, update `yt-dlp` to get the latest decoders:
  ```bash
  yt-dlp -U
  ```
- **Warning: mpv exited?** Ensure `mpv` is compiled with Lua support. Most native distribution package managers compile it with Lua support by default.
- **Searching Fails?** Ensure Neovim has internet access and your geographic region is not blocked or rate-limited by YouTube's API filters.

---

## ❓ FAQ

**Q: Does this download videos to my computer?**  
A: No. It streams only the audio tracks in real-time, saving disk space and bandwidth.

**Q: Can multiple Neovim instances control the same audio?**  
A: Yes! A shared client registry coordinates instances. When you start audio in one instance, others can view the statusline or control the active player.

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome!  
Check out our [Contributing Guidelines](CONTRIBUTING.md) to get started with local testing and architectural details.

---

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for more information.
