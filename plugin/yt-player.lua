-- plugin/yt-player.lua
-- Prevents duplicate plugin loads.

if vim.g.yt_control_loaded then
	return
end

-- Ensure :YT user command is always available with default setup fallback
if vim.fn.exists(":YT") == 0 then
	vim.api.nvim_create_user_command("YT", function(opts)
		if not vim.g.yt_control_loaded then
			require("yt-player").setup({})
		end
		local args = opts.args or ""
		if args ~= "" then
			vim.cmd("YT " .. args)
		else
			require("yt-player.ui.hub").toggle()
		end
	end, {
		desc = "YT Control Master Command",
		nargs = "*",
		complete = function(ArgLead, CmdLine, CursorPos)
			if not vim.g.yt_control_loaded then
				require("yt-player").setup({})
			end
			return vim.fn.getcompletion(CmdLine, "cmdline")
		end,
	})
end
