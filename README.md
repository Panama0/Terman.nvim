# Terman.nvim
Simple terminal session management

## Features
- Run terminal jobs in a buffer you can hide
- Preset or arbitrary terminal jobs
- Customisable with user defined functions to run before/after a job
- Floating or split pane

## Usage
The command ':Terman' will run the preset or terminal command you pass in, prefering to run presets if there is a name clash.
You can also call `open()` and pass in an existing or new preset.
Presets can be searched with `get_session_preset` by passing in the name of the session (or cmd if no name was provided).

When in a terminal, '<esc><esc>' will hide the window.

## Config
Below is the default config:

```lua
local config = {
	presets = {
		{
			name = "Terminal",
			cmd = "fish",
		},
	},
	window_options = {
		floating_width = 0.8,
		floating_height = 0.8,
		split_height = 0.2,
	},
}
```

Add as many presets as you like using the below fields:

```lua
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

---@class terman.Config
---@field presets terman.Preset[]
---@field window_options terman.WindowOptions
```

## Examples
Using on_exit and pre_open callbacks to open a chosen file with Yazi:
```lua
config = function()
  local function setup_yazi()
    local yazi_dir = vim.fn.stdpath 'data' .. '/yazi'
    local file = yazi_dir .. '/chooser-file.txt'

    -- make file if not there
    if vim.fn.isdirectory(yazi_dir) == 0 then
      vim.fn.mkdir(yazi_dir, 'p')
    end
    local f = io.open(file, 'w')
    f:close()
  end

  local function open_chooser_file()
    local yazi_dir = vim.fn.stdpath 'data' .. '/yazi'
    local file = yazi_dir .. '/chooser-file.txt'

    local f = io.open(file, 'r')
    chosenFile = f:read '*l'
    f:close()

    if chosenFile then
      vim.cmd('e ' .. chosenFile)
    end
  end

  local opts = {
    presets = {
      {
        name = 'Terminal',
        cmd = 'fish',
        pos = 'bottom',
      },
      {
        name = 'Lazygit',
        cmd = 'lazygit',
      },
      {
        name = 'Yazi',
        cmd = 'yazi --chooser-file ~/.local/share/nvim/yazi/chooser-file.txt',
        pre_open = setup_yazi,
        on_exit = open_chooser_file,
      },
    },
  }

  require('terman').setup(opts)
end
```
