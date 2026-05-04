# 🎵 nvim-yt-player

Play YouTube audio directly from Neovim using **mpv** + **yt-dlp**. No browser, no Node.js — just pure Lua talking to mpv over a local IPC socket.

## ✨ Features

- **▶️ Seamless Playback**: Play any YouTube URL or search query instantly via a simple Neovim command.
- **🏗️ Zero-Dependency Backend**: Runs entirely on pure Lua via a local UNIX socket. No browser extension, no Node.js requirement, no external bloated servers. Just `mpv` and `yt-dlp`.
- **🎨 Premium ASCII Visualizer UI**: Implements a dedicated (`:YT player`) animated player layout featuring a custom bounding-box grid, bouncy audio visualizer, interactive progress slidebar, and built-in queue alignment.
- **🔍 Interactive Search Picker**: Search YouTube directly inside Neovim and preview video durations/channels in a native floating window buffer.
- **📁 Local Playlists**: Save tracks into custom, locally-stored playlists using `s`. Manage and play them entirely within the split-pane manager (`:YT playlists`).
- **📝 Interactive Queue Editor**: View and modify your active queue in real-time. Use `dd` to remove tracks or `J`/`K` to reorder them (`:YT queue_edit`).
- **🎵 Endless Queuing & YouTube Playlists**: Instantly append streams or search results to your queue. You can even pass a full YouTube Playlist URL to rapidly ingest 100+ tracks (`:YT queue_playlist`).
- **⏩ SponsorBlock Integration**: Natively caches and injects an mpv script to automatically skip sponsor and intro segments in YouTube videos (enable via config).
- **🎛️ Total Control**: Full mappings to Play/Pause, Seek, Skip, Mute, Volume, and manipulate Playback Speed (0.25x – 3.0x).
- **📊 Statusline Integration**: Formats progress bars smoothly for plugins like `lualine`
- **🔔 Asynchronous Stability**: Stream fetching runs in the background. Neovim will never freeze or block while caching metadata or traversing tracks.

## 📦 Requirements

| Dependency | Install |
|------------|---------|
| [Neovim](https://neovim.io/) 0.9+ | — |
| [mpv](https://mpv.io/) | `sudo apt install mpv` or `brew install mpv` |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | `pip install yt-dlp` or [binary release](https://github.com/yt-dlp/yt-dlp/releases) |

## 🔧 Installation

### lazy.nvim

```lua
{
  "sanjay-np/nvim-yt-player",
  config = function()
    require("yt-player").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "sanjay-np/nvim-yt-player",
  config = function()
    require("yt-player").setup()
  end,
}
```

## 🚀 Quick Start

```vim
:YT play https://www.youtube.com/watch?v=dQw4w9WgXcQ
```

Or search directly from Neovim (opens in a custom interactive floating window!):

```vim
:YT search lofi hip hop
```

In the interactive search window:
- `<CR>` (Enter): Play result (replaces current track)
- `<C-a>` (Ctrl+A) or `a` / `A` (in Normal mode): Append result to the queue
- `s` (in Normal mode): Save track to a Local Playlist

## 📋 Commands

All functionality is grouped under a single `:YT` command with auto-completion (press `Tab`!).

| Command | Description |
|---------|-------------|
| `:YT play [url]` | Play URL / search, or resume |
| `:YT search [query]` | 🔍 Search YouTube and pick a result |
| `:YT queue <url>` | Append a single URL to the playlist |
| `:YT queue_playlist <url>` | Fetch and append an entire playlist |
| `:YT queue_edit` | Open interactive queue editor |
| `:YT pause` | Pause |
| `:YT toggle` | Toggle play/pause |
| `:YT stop` | Stop playback |
| `:YT next` / `:YT prev` | Next / previous track |
| `:YT seek <sec>` | Seek to absolute position |
| `:YT seek_rel <±sec>` | Seek relative |
| `:YT volume <0-100>` | Set volume |
| `:YT vol_up` / `:YT vol_down` | Volume ±5 |
| `:YT mute` | Toggle mute |
| `:YT speed [arg]` | Set/adjust speed — see forms below |
| `:YT shuffle` / `:YT repeat_toggle`| Shuffle / repeat |
| `:YT player` | Toggle the player side-panel |
| `:YT player float` | Toggle the floating player window |
| `:YT history` | Browse play history |
| `:YT history_clear` | Clear play history |
| `:YT playlists` | Manage and play local custom playlists |
| `:YT radio` | Toggle radio/autoplay mode |

### Speed Command Forms

| Invocation | Behaviour |
|---|---|
| `:YT speed` | Show current speed |
| `:YT speed 1.5` | Set speed absolutely (0.25 – 3.0) |
| `:YT speed up` | Increase by +0.25× |
| `:YT speed down` | Decrease by −0.25× |
| `:YT speed +0.5` | Increase by a custom delta |
| `:YT speed -0.5` | Decrease by a custom delta |

## 🎛️ Player Windows

`:YT player` (side-panel) and `:YT player float` (floating window) share the same controls:

| Key | Action |
|-----|--------|
| `p` / `s` / `t` | Play / Pause / Toggle |
| `n` / `b` | Next / Previous |
| `m` | Mute |
| `>` / `<` | Speed ±0.25 |
| `+` / `-` | Volume ±5 |
| `l` / `h` | Seek ±5s |
| `L` / `H` | Seek ±30s |
| `r` | Toggle Radio mode |
| `q` / `<Esc>` | Close |

## ⚙️ Configuration

All options with defaults:

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

  -- Search settings
  search = {
    limit = 10, -- number of results to fetch
  },

  notifications = {
    enabled = true,
    notify_on_track_change = true,
  },

  player = {
    queue_display_limit = 5, -- Number of upcoming tracks to show in the `:YT player` side-panel
  },

  keymaps = {
    enabled = false,
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
  
  sponsorblock = false, -- Set to true to automatically skip embedded sponsor segments
})
```

### Statusline Placeholders

`{icon}` `{title}` `{artist}` `{album}` `{position}` `{duration}` `{volume}` `{progress}` `{speed}`

Example output: `▶ Song Name ▓▓▓▓░░░░░░ [2:30/5:00] 1.5x`

## 📊 Lualine Integration

```lua
require("lualine").setup({
  sections = {
    lualine_x = { "yt-player" }
  }
})
```

## 🏗️ Architecture

```
Neovim (Lua) ←─ IPC pipe ─→ mpv ←── yt-dlp ←── YouTube
```

The plugin spawns a headless `mpv --no-video` process and communicates through a UNIX domain socket using mpv's JSON IPC protocol. `yt-dlp` is used by mpv internally to resolve YouTube URLs into streamable media.

## 🔧 Troubleshooting

- **No audio**: Run `mpv --no-video <youtube-url>` directly to verify mpv + yt-dlp work
- **yt-dlp outdated**: Run `yt-dlp -U` to update
- **Socket issues**: The IPC socket is stored in Neovim's cache directory
- **"Socket already in use"**: Another mpv process may be running. Kill with `pkill -f "mpv.*yt-player"` or restart Neovim
- **Search not working**: Ensure `yt-dlp` can access YouTube (check for API rate limits or geo-blocking)
- **Player window not showing**: Ensure `mpv` was compiled with lua support (most distributions include it)

## ❓ FAQ

**Q: How do I play audio only (no video)?**
A: The plugin automatically runs `mpv --no-video` by default. Video is disabled to save resources.

**Q: Can I use this with YouTube Music?**
A: Yes! Any YouTube URL works. For music videos, you'll get the audio track with album art in the player window.

**Q: Does this work with playlists?**
A: Yes. Use `:YT queue_playlist <playlist-url>` to load an entire playlist, or `:YT queue <url>` for individual tracks.

**Q: How does the radio mode work?**
A: When enabled (press `r` in player window or `:YT radio`), the plugin will automatically queue and play related videos when the queue ends—creating an endless listening experience.

**Q: Can I use keyboard shortcuts globally?**
A: Yes! Enable global keymaps in config:
```lua
keymaps = {
  enabled = true,
  prefix = "<leader>y",
  -- ... other mappings
}
```

## ⌨️ Keyboard Shortcuts Cheatsheet

| Category | Key | Action |
|----------|-----|--------|
| **Playback** | `p` | Play |
| | `s` | Pause |
| | `t` | Toggle play/pause |
| **Navigation** | `n` | Next track |
| | `b` | Previous track |
| | `l` / `h` | Seek ±5s |
| | `L` / `H` | Seek ±30s |
| **Volume** | `m` | Mute toggle |
| | `+` / `-` | Volume ±5 |
| **Speed** | `>` | Speed +0.25 (`speed up`) |
| | `<` | Speed −0.25 (`speed down`) |
| **Mode** | `r` | Toggle radio mode |
| **Exit** | `q` / `Esc` | Close player |

## 📄 License

MIT
