vim.api.nvim_create_user_command("Terman", function(opts)
	local args = opts.args ~= "" and opts.args or nil

	local session = require("terman").get_session_preset(args)

	if session then
		require("terman").open(session)
	else
		require("terman").open({ cmd = args })
	end
end, {
	nargs = "?", -- 0 or 1 args only
	complete = "shellcmd", -- optional: shell command completion
})
