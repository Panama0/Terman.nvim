local M = {}

---@class terman.WindowOptions
---@field floating_width number Width of floating windows
---@field floating_height number Height of floating windows
---@field split_height number Height of split windows
---@field navigate_up string Keybind to navigate up from terman windows (terminal mode)
---@field navigate_down string Keybind to navigate down from terman windows (terminal mode)

---@class terman.Preset
---@field name string? Name that can be used to retrieve the session
---@field cmd string? Command to run
---@field on_exit function? Function to run on command exit, exit code is passed in
---@field pre_open function? Function to run once upon session creation
---@field pos? 'floating' | 'top' | 'bottom' Window position, default floating
---@field persist? boolean if true, terminal will stay open after job completion

---@class terman.Config
---@field presets terman.Preset[]
---@field window_options terman.WindowOptions

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
		navigate_up = "<C-k>",
		navigate_down = "<C-j>",
	},
}

---@class terman.ActiveState
---@field win number Nvim window id
---@field buf number Nvim buffer id
---@field name string Terman identifier, preset name or cmd
---@field dead boolean? Whether the buffer is dead

-- active windows and buffers
---@type table<string, terman.ActiveState>
local active_state = {}

---@param buf number Nvim buffer to bind to
---@param name string Name from preset
---@param pos? "floating" | "top" | "bottom" Position for terminal window, default to floating
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
	vim.notify(vim.inspect(active_state), "info", { title = "Terman" })
end

---@param session terman.ActiveState
local function kill_session(session)
	if vim.api.nvim_win_is_valid(session.win) then
		vim.api.nvim_win_close(session.win, true)
	end

	vim.api.nvim_buf_delete(session.buf, { force = true })
	active_state[session.name] = nil
end

--FIX: if the window is the last one, we cant hide!
-- in this case we will have to open a new window first, then hide

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

			if session.dead then
				kill_session(session)
				return
			end

			return
		end
	end

	vim.notify("Not in a buffer managed by Terman...", "error", { title = "Terman" })
end

-- Finds session preset with key, returns false if no session exists
---@param key string: Key or cmd to find
M.get_session_preset = function(key)
	for _, p in ipairs(config.presets) do
		if p.name == key then
			return p
		end
	end
	vim.notify("No preset found for: " .. key, "error", { title = "Terman" })
	return false
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
			-- if the window is open, we can just focus it
			if vim.api.nvim_win_is_valid(saved_session.win) then
				vim.api.nvim_set_current_win(saved_session.win)
				return
			end

			saved_session.win = create_window(saved_session.buf, key, session.pos)
			vim.cmd("startinsert")
			return
		end
		-- if the buf is dead, it will be recreated below
	end

	local source_window = vim.api.nvim_get_current_win()

	local b = vim.api.nvim_create_buf(false, true)
	local w = create_window(b, key, session.pos)
	saved_session = {
		buf = b,
		win = w,
		name = key,
	}

	active_state[key] = saved_session

	-- pre open if specified
	if session.pre_open then
		session.pre_open()
	end

	-- setup command, start a second shell session if persisting
	local shell = os.getenv("SHELL") or "sh"
	local cmd = session.cmd or shell
	-- set up buffer
	vim.api.nvim_buf_call(b, function()
		local job_id = vim.fn.jobstart(cmd, {
			term = true,
			on_exit = function(_, code, _)
				vim.schedule(function()
					if not session.persist then
						kill_session(saved_session)
						if session.on_exit then
							session.on_exit(code)
						else
							vim.notify("Terminal exited with code " .. code, "info", { title = "Terman" })
						end

						return
					end

					-- force insert mode
					vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "n", false)
					-- disable terminal mode
					vim.keymap.set("n", "i", "<nop>", { buffer = saved_session.buf })

					-- it will be killed when we hide the buffer
					saved_session.dead = true
				end)
			end,
		})
		if job_id == 0 then
			vim.notify("Failed to start terminal: " .. cmd, "error", { title = "Terman" })
			kill_session(saved_session)
			return
		end
	end)

	vim.api.nvim_create_autocmd("BufEnter", {
		desc = "Enter insert mode in Terman buffers",
		group = vim.api.nvim_create_augroup("Terman-insert", { clear = true }),
		buffer = saved_session.buf,
		callback = function()
			vim.cmd("startinsert")
		end,
	})

	-- add a keybind just for this buffer to hide the terminal
	vim.keymap.set({ "t", "n" }, "<esc><esc>", M.hide, { buffer = saved_session.buf })
	-- other keybinds
	vim.keymap.set("t", config.window_options.navigate_up, "<C-\\><C-n><C-w>k", { buffer = saved_session.buf })
	vim.keymap.set("t", config.window_options.navigate_down, "<C-\\><C-n><C-w>j", { buffer = saved_session.buf })

	vim.cmd("startinsert")
end

return M
