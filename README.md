# 🎵 nvim-yt-player

Play YouTube audio directly from Neovim using **mpv** + **yt-dlp**. No browser, no Node.js — just pure Lua talking to mpv over a local IPC socket.

## ✨ Features

- ▶️ Play any YouTube URL or search query from a Neovim command
- ⏯ Play / Pause / Stop / Next / Previous
- 🔊 Volume & mute control
- ⏩ Seek (absolute & relative)
- 🏎️ Playback speed (0.25x – 3.0x)
- 🔀 Shuffle & repeat
- 📊 Statusline integration with progress bar (lualine supported)
- 🎛️ Interactive floating player window with keymaps
- 🔔 Track change notifications
- 🚀 Zero external dependencies beyond `mpv` and `yt-dlp`

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

## 📋 Commands

All functionality is grouped under a single `:YT` command with auto-completion (press `Tab`!).

| Command | Description |
|---------|-------------|
| `:YT play [url]` | Play URL / search, or resume |
| `:YT search [query]` | 🔍 Search YouTube and pick a result |
| `:YT queue <url>` | Append a URL to the playlist |
| `:YT pause` | Pause |
| `:YT toggle` | Toggle play/pause |
| `:YT stop` | Stop playback |
| `:YT next` / `:YT prev` | Next / previous track |
| `:YT seek <sec>` | Seek to absolute position |
| `:YT seek_rel <±sec>` | Seek relative |
| `:YT volume <0-100>` | Set volume |
| `:YT vol_up` / `:YT vol_down` | Volume ±5 |
| `:YT mute` | Toggle mute |
| `:YT speed <rate>` | Set speed (0.25–3.0) |
| `:YT speed_up` / `:YT speed_down` | Speed ±0.25 |
| `:YT shuffle` / `:YT repeat_toggle`| Shuffle / repeat |
| `:YT ui` | Toggle the dedicated player side-panel |
| `:YT info` | Toggle the floating player window |

## 🎛️ Floating Player

`:YTInfo` opens an interactive floating window:

| Key | Action |
|-----|--------|
| `p` / `s` / `t` | Play / Pause / Toggle |
| `n` / `b` | Next / Previous |
| `m` | Mute |
| `>` / `<` | Speed ±0.25 |
| `+` / `-` | Volume ±5 |
| `l` / `h` | Seek ±5s |
| `L` / `H` | Seek ±30s |
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
    notify_on_command = false,
  },

  keymaps = {
    enabled = false,
    prefix = "<leader>y",
  },
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
- **Port conflict**: The IPC socket path is `/tmp/nvim-yt-player-ipc-<pid>`, unique per Neovim instance

## 📄 License

MIT
