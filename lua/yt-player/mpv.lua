local M = {}

local uv = vim.loop
local state_mod = require("yt-player.state")

M.config = {}
M.mpv_job_id = nil
M.ipc_pipe = nil
M.ipc_connected = false
M.ipc_socket_path = "/tmp/nvim-yt-player-ipc-" .. vim.fn.getpid()

M.shutting_down = false

-- IPC buffer (mpv sends JSON strings separated by newlines)
local ipc_buffer = ""

-- Pending commands to send once IPC is connected
local pending_commands = {}

function M.setup(config)
  M.config = config
  M.shutting_down = false
end

--- Start mpv with IPC enabled. If a url is provided, it is passed directly
--- on the command line so playback begins immediately without waiting for IPC.
---@param url string|nil  Optional URL to play immediately
function M.start(url)
  if M.shutting_down then return false end

  if M.is_running() then
    return true
  end

  -- Ensure yt-dlp and mpv exist
  if vim.fn.executable("mpv") == 0 then
    vim.notify("YT Control: mpv is not installed or not in PATH", vim.log.levels.ERROR)
    return false
  end
  if vim.fn.executable("yt-dlp") == 0 then
    vim.notify("YT Control: yt-dlp is not installed or not in PATH", vim.log.levels.ERROR)
    return false
  end

  -- Remove stale socket file from previous crashed sessions
  vim.fn.delete(M.ipc_socket_path)

  local cmd = {
    "mpv",
    "--no-video",
    "--no-terminal",
    "--input-ipc-server=" .. M.ipc_socket_path,
  }

  -- If we have a URL, pass it directly so playback starts immediately
  -- Otherwise start in idle mode
  if url then
    table.insert(cmd, url)
  else
    table.insert(cmd, "--idle=yes")
  end

  local stderr_lines = {}

  M.mpv_job_id = vim.fn.jobstart(cmd, {
    detach = true,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then stderr_lines[#stderr_lines + 1] = line end
        end
      end
    end,
    on_exit = function(_, code)
      M.mpv_job_id = nil
      M.ipc_connected = false
      M._cleanup_ipc()
      state_mod.set_connected(false)
      if code ~= 0 and code ~= 143 and code ~= 15 and not M.shutting_down then
        vim.schedule(function()
          local err_msg = #stderr_lines > 0 and ("\n" .. table.concat(stderr_lines, "\n")) or ""
          vim.notify("YT Control: mpv exited (code " .. code .. ")" .. err_msg, vim.log.levels.WARN)
        end)
      end
    end
  })

  if M.mpv_job_id <= 0 then
    vim.notify("YT Control: Failed to start mpv process", vim.log.levels.ERROR)
    M.mpv_job_id = nil
    return false
  end

  -- Wait briefly for socket to be created by mpv, then connect IPC
  M._connect_ipc_with_retry(0)

  return true
end

function M.is_running()
  return M.mpv_job_id ~= nil
end

--- Try to connect to IPC socket with retries (mpv needs a moment to create it)
---@param attempt number  Current retry attempt
function M._connect_ipc_with_retry(attempt)
  if M.shutting_down then return end
  if not M.is_running() then return end

  local max_attempts = 10
  local delay = 300 -- ms between retries

  vim.defer_fn(function()
    if M.shutting_down or not M.is_running() then return end

    M.ipc_pipe = uv.new_pipe(false)
    M.ipc_pipe:connect(M.ipc_socket_path, function(err)
      if err then
        -- Clean up failed pipe
        pcall(function()
          if M.ipc_pipe and not M.ipc_pipe:is_closing() then
            M.ipc_pipe:close()
          end
        end)
        M.ipc_pipe = nil

        if attempt < max_attempts then
          vim.schedule(function()
            M._connect_ipc_with_retry(attempt + 1)
          end)
        else
          vim.schedule(function()
            if M.shutting_down then return end
            vim.notify("YT Control: Failed to connect to mpv IPC after " .. max_attempts .. " attempts",
              vim.log.levels.ERROR)
          end)
        end
        return
      end

      -- Successfully connected!
      M.ipc_connected = true

      vim.schedule(function()
        if M.shutting_down then return end
        state_mod.set_connected(true)
        vim.notify("YT Control: Connected to mpv", vim.log.levels.INFO)

        -- Enable property observers
        M.send_command({ "observe_property", 1, "time-pos" })
        M.send_command({ "observe_property", 2, "pause" })
        M.send_command({ "observe_property", 3, "duration" })
        M.send_command({ "observe_property", 4, "volume" })
        M.send_command({ "observe_property", 5, "mute" })
        M.send_command({ "observe_property", 6, "speed" })
        M.send_command({ "observe_property", 7, "media-title" })
        M.send_command({ "observe_property", 8, "playlist" })
        M.send_command({ "observe_property", 9, "playlist-pos" })
        M.send_command({ "observe_property", 10, "playlist-count" })

        -- Flush any pending commands that were queued before IPC was ready
        M._flush_pending()
      end)

      M.ipc_pipe:read_start(function(read_err, data)
        if M.shutting_down then return end
        if read_err then
          vim.schedule(function()
            M.ipc_connected = false
            M._cleanup_ipc()
          end)
          return
        end

        if data then
          ipc_buffer = ipc_buffer .. data
          M._process_ipc_buffer()
        else
          -- EOF
          vim.schedule(function()
            M.ipc_connected = false
            M._cleanup_ipc()
          end)
        end
      end)
    end)
  end, delay)
end

--- Flush pending commands that were queued before IPC was ready
function M._flush_pending()
  local cmds = pending_commands
  pending_commands = {}
  for _, cmd in ipairs(cmds) do
    M.send_command(cmd)
  end
end

function M._process_ipc_buffer()
  while true do
    local newline_pos = ipc_buffer:find("\n")
    if not newline_pos then
      break
    end

    local line = ipc_buffer:sub(1, newline_pos - 1)
    ipc_buffer = ipc_buffer:sub(newline_pos + 1)

    if line ~= "" then
      vim.schedule(function()
        if M.shutting_down then return end
        M._handle_ipc_message(line)
      end)
    end
  end
end

function M._handle_ipc_message(line)
  if M.shutting_down then return end

  local ok, msg = pcall(vim.json.decode, line)
  if not ok then return end

  -- Handle Property Changes
  if msg.event == "property-change" then
    local updates = {}

    if msg.name == "time-pos" then
      updates.position = msg.data or 0
    elseif msg.name == "duration" then
      updates.duration = msg.data or 0
    elseif msg.name == "pause" then
      updates.playing = not msg.data
    elseif msg.name == "volume" then
      updates.volume = msg.data or 100
    elseif msg.name == "mute" then
      updates.muted = msg.data or false
    elseif msg.name == "speed" then
      updates.speed = msg.data or 1
    elseif msg.name == "media-title" then
      updates.title = msg.data or "Unknown"
    elseif msg.name == "playlist" then
      updates.playlist = msg.data or {}
    elseif msg.name == "playlist-pos" then
      updates.playlist_pos = msg.data or 0
    elseif msg.name == "playlist-count" then
      updates.playlist_count = msg.data or 0
    end

    -- Push to state
    if not vim.tbl_isempty(updates) then
      state_mod.update(updates)
    end

    -- Handle events
  elseif msg.event == "end-file" then
    -- Stream ended safely
    if msg.reason ~= "stop" and msg.reason ~= "quit" then
      state_mod.update({
        playing = false,
        position = 0,
        title = "Finished",
      })
    end
  end
end

--- Send a raw JSON IPC command to mpv
--- If IPC isn't connected yet but mpv is running, queue the command.
---@param command_list table E.g. {"set_property", "pause", true}
function M.send_command(command_list)
  if M.shutting_down then return false end

  -- If IPC isn't ready yet but mpv is running, queue the command
  if not M.ipc_connected or not M.ipc_pipe then
    if M.is_running() then
      table.insert(pending_commands, command_list)
      return true -- queued
    end
    return false
  end

  if M.ipc_pipe:is_closing() then
    return false
  end

  local ok, json = pcall(vim.json.encode, { command = command_list })
  if not ok then return false end

  pcall(function()
    M.ipc_pipe:write(json .. "\n")
  end)

  return true
end

--- High-level control function: Load URL
function M.load_url(url)
  if not M.is_running() then
    -- Start mpv with the URL directly on the command line — no IPC race!
    M.start(url)
  else
    -- mpv is already running, use IPC to load the new file
    M.send_command({ "loadfile", url, "replace" })
  end

  -- Optimistically set UI title while yt-dlp resolves the stream
  state_mod.update({
    title = "Loading...",
    playing = false,
    position = 0,
    duration = 0,
    artist = ""
  })
end

function M._cleanup_ipc()
  if M.ipc_pipe then
    pcall(function()
      M.ipc_pipe:read_stop()
      if not M.ipc_pipe:is_closing() then
        M.ipc_pipe:close()
      end
    end)
    M.ipc_pipe = nil
  end
  M.ipc_connected = false
  ipc_buffer = ""
end

function M.shutdown()
  M.shutting_down = true
  M._cleanup_ipc()

  if M.is_running() then
    local id = M.mpv_job_id
    M.mpv_job_id = nil
    pcall(function()
      vim.fn.jobstop(id)
    end)
  end
end

return M
