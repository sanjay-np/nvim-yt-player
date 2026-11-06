# Contributing to nvim-yt-player

Thank you for your interest in contributing to **nvim-yt-player**! 🎉 

Whether you're fixing a bug, adding new controls, improving documentation, or optimizing performance, all contributions are welcome.

---

## 🏛️ Codebase Overview

The codebase is written in pure Lua (compatible with LuaJIT in Neovim 0.9+) and structured cleanly into modular components:

- **[`lua/yt-player/mpv.lua`](lua/yt-player/mpv.lua)**: Core UNIX domain socket IPC driver that communicates directly with background `mpv`.
- **[`lua/yt-player/radio.lua`](lua/yt-player/radio.lua)**: Autoplay recommendation engine that fetches YouTube Mix tracks via `yt-dlp` in the background with cooldown guards.
- **[`lua/yt-player/search.lua`](lua/yt-player/search.lua)**: Async `yt-dlp` search with pagination (rendered by the Hub's Search tab) and YouTube playlist import.
- **[`lua/yt-player/player.lua`](lua/yt-player/player.lua)**: Shared transport layout, live progress, and floating/sidebar player windows.
- **[`lua/yt-player/ui/`](lua/yt-player/ui/)**: Unified hub, responsive views, display-width helpers, themes, and visualizers.
- **[`lua/yt-player/state.lua`](lua/yt-player/state.lua)**: Central playback state store synchronized with mpv property changes.
- **[`lua/yt-player/playlists.lua`](lua/yt-player/playlists.lua)**: Local playlists persisted to `stdpath("data")` (managed in the Hub's Playlists tab).
- **[`lua/yt-player/history.lua`](lua/yt-player/history.lua)**: Persistent play history tracker.
- **[`lua/yt-player/session.lua`](lua/yt-player/session.lua)**: Automatic session saving and resume engine.
- **[`lua/yt-player/status.lua`](lua/yt-player/status.lua)** & **[`lua/lualine/components/yt-player.lua`](lua/lualine/components/yt-player.lua)**: High-performance statusline and lualine formatters.
- **[`lua/yt-player/utils.lua`](lua/yt-player/utils.lua)**: Shared utilities (binary-search `safe_truncate`, `ensure_dir`, time formatting).
- **[`lua/yt-player/commands.lua`](lua/yt-player/commands.lua)**: User-facing `:YT` command router with multi-level autocompletion.

---

## 🧪 Local Testing & Verification

Before submitting a PR, make sure all modules and tests run cleanly in headless Neovim:

```bash
nvim --headless -u NONE -c 'set rtp+=.' -c 'lua
local modules = {
  "yt-player",
  "yt-player.commands",
  "yt-player.history",
  "yt-player.init",
  "yt-player.keymaps",
  "yt-player.mpv",
  "yt-player.notify",
  "yt-player.player",
  "yt-player.playlists",
  "yt-player.radio",
  "yt-player.search",
  "yt-player.session",
  "yt-player.state",
  "yt-player.status",
  "yt-player.utils",
}

for _, mod in ipairs(modules) do
  assert(pcall(require, mod), "Failed to load module: " .. mod)
end

require("yt-player").setup({})
require("yt-player.commands").setup()
print("All local verification tests passed!")
' -c 'q'
```

The UI regression suite uses offline fixture data and stubbed playback commands.
It checks responsive layouts, Unicode titles, selection after scrolling,
search response ordering, playlist edits, and window cleanup:

```bash
nvim --headless -u NONE -i NONE -n -c 'set rtp+=.' -c 'lua dofile("tests/ui_spec.lua")'
```

The core regression suite covers playback and persistence logic offline (no mpv,
yt-dlp, or network): session resume, track-change notifications, corrupt data
file recovery, SponsorBlock script refresh, multi-instance attach, radio
fetches that are cancelled or overtaken by a track change, and player window
hygiene (no undo history, tabpage-aware toggling, theme refresh):

```bash
nvim --headless -u NONE -i NONE -n -c 'set rtp+=.' -c 'lua dofile("tests/core_spec.lua")'
```

---

## 🎨 Code Style & Best Practices

1. **Neovim Compatibility**: Standardize all Libuv API calls on `local uv = vim.uv or vim.loop` at the top of files.
2. **Ephemeral Buffers**: Always set `vim.bo[buf].bufhidden = "wipe"` for temporary floating windows and side panels to prevent memory leaks.
3. **No UI Blocking**: Never run blocking filesystem or network operations on the main thread. Always leverage asynchronous pipes (`uv.new_pipe`) or `vim.schedule`.
4. **Data Persistence**: Always use `utils.ensure_dir(filepath)` before writing persistent data to `stdpath("data")`.
5. **Preserve Documentation**: Maintain existing docstrings and comments.

---

## 🚀 Submitting Pull Requests

1. Fork the repository and create your branch from `master`.
2. Commit your changes with clear, descriptive commit messages.
3. Run the headless verification tests locally.
4. Open a Pull Request on GitHub using the provided PR template.
