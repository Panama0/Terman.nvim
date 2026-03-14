local M = {}

---@class terman.WindowOptions
---@field floating_width number: Width of floating windows
---@field floating_height number: Height of floating windows
---@field split_height number: Height of split windows

---@class terman.Preset
---@field name string?: Name that can be used to retrieve the session
---@field cmd string: Command to run
---@field on_exit function?: Function to run on command exit
---@field pre_open function?: Function to run once upon session creation
---@field pos? 'floating' | 'top' | 'bottom': Window position, default floating
---@field persist? boolean: if true, terminal will stay open after job completion

---@class terman.Config
---@field presets terman.Preset[]
---@field window_options terman.WindowOptions

---@class ActiveState
---@field win number: Nvim window id
---@field buf number: Nvim buffer id
---@field name string: Terman identifier, preset name or cmd

---@type terman.Config
local config = {
	presets = {
		{
			name = "Terminal",
		},
	},
	window_options = {
		floating_width = 0.8,
		floating_height = 0.8,
		split_height = 0.2,
	},
}

-- active windows and buffers
local active_state = {}

---@param buf number: Nvim buffer to bind to
---@param name string: Name from preset
---@param pos? "floating" | "top" | "bottom": Position for terminal window, default to floating
local function create_window(buf, name, pos)
	pos = pos or "floating"

	if pos == "floating" then
		local width = math.floor(vim.o.columns * config.window_options.floating_width)
		local height = math.floor(vim.o.lines * config.window_options.floating_height)

		local col = math.floor((vim.o.columns - width) / 2)
		local row = math.floor((vim.o.lines - height) / 2)

		-- Define window configuration
		local float_config = {
			relative = "editor",
			width = width,
			height = height,
			col = col,
			row = row,
			style = "minimal", -- No borders or extra UI elements
			border = "rounded",
			title = { { name, "FloatBorder" } },
			title_pos = "center",
		}

		-- Create the floating window
		return vim.api.nvim_open_win(buf, true, float_config)
	end

	-- split
	local split_config = {
		win = -1,
		height = math.floor(vim.o.lines * config.window_options.split_height),
	}

	if pos == "top" then
		split_config.split = "above"
	elseif pos == "bottom" then
		split_config.split = "below"
	end

	return vim.api.nvim_open_win(buf, true, split_config)
end

---@param opts terman.Config
M.setup = function(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

--TODO: in future, this should have some kind of gui element where we can kill sessions
M.ls = function()
	vim.print(active_state)
end

-- Hide current session
M.hide = function()
	local current_buf = vim.api.nvim_get_current_buf()

	-- Only act if we're in a terminal buffer
	if vim.bo.buftype ~= "terminal" then
		return
	end

	-- Find the session it belongs to
	for _, session in pairs(active_state) do
		if session.buf == current_buf and vim.api.nvim_win_is_valid(session.win) then
			vim.api.nvim_win_hide(session.win)
			return
		end
	end

	print("Not in a buffer managed by Terman...")
end

-- Finds session preset with key, returns false if no session exists
---@param key string: Key or cmd to find
M.get_session_preset = function(key)
	for _, p in ipairs(config.presets) do
		if p.name == key then
			return p
		end
	end
end

-- Opens or creates a session.
-- Optionally takes in a key that can be used to store and retrieve sessions, otherwise the cmd is used.
---@param session terman.Preset
M.open = function(session)
	local key = session.name or session.cmd or "Terminal"

	local saved_session = active_state[key]

	-- restore last session
	if saved_session then
		if vim.api.nvim_buf_is_valid(saved_session.buf) then
			saved_session.win = create_window(saved_session.buf, key, session.pos)
			vim.cmd("startinsert")
			return
		end
		-- if the buf is dead, it will be recreated below
	end

	local b = vim.api.nvim_create_buf(false, true)
	local w = create_window(b, key, session.pos)
	saved_session = {
		buf = b,
		win = w,
		name = key,
	}

	active_state[key] = saved_session

	-- pre open if needed
	if session.pre_open then
		session.pre_open()
	end

	-- setup command, start a second shell session if persisting
	local cmd
	local shell = os.getenv("SHELL") or "sh"

	if session.cmd then
		if session.persist then
			cmd = { shell, "-c", session.cmd .. "; exec " .. shell }
		else
			cmd = session.cmd
		end
	else
		cmd = shell
	end

	-- set up buffer
	vim.fn.jobstart(cmd, {
		term = true,
		on_exit = function(_, code, _)
			if vim.api.nvim_win_is_valid(saved_session.win) then
				vim.api.nvim_win_close(saved_session.win, true)
			end

			vim.api.nvim_buf_delete(saved_session.buf, { force = true })

			if session.on_exit then
				session.on_exit()
			else
				print("Terminal exited with code " .. code)
			end
			-- remove the session
			active_state[saved_session.name] = nil
		end,
	})

	-- add a keybind just for this buffer to hide the terminal
	vim.keymap.set("t", "<esc><esc>", M.hide, { buffer = saved_session.buf })
	vim.cmd("startinsert")
end

return M
