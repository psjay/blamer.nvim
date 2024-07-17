# Blamer

Blamer is a Neovim plugin for displaying Git blame information in [vim-fugitive](https://github.com/tpope/vim-fugitive) style with some enhancements.
## Features

- Display Git blame information side by side
- Real-time updates of blame information as you edit
- Customizable date format and window width

## Installation

Install Blamer using your preferred plugin manager. For example, with [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'psjay/blamer.nvim',
  config = function()
    require('blamer').setup()
  end
}
```

## Configuration

Blamer can be configured through the `setup` function. Here are the default settings and available options:

```lua
require('blamer').setup({
  date_format = "%Y-%m-%d %H:%M",  -- Date format
  window_width = 40,               -- Width of the blame window
  show_summary = true              -- Whether to show commit summaries
})
```

## Usage

Blamer provides a command to toggle the display of blame information:

- `:BlamerToggle` - Toggle the display of the blame information window

In the blame window, you can use the following shortcuts:

- `q` or `<ESC>` - Close the blame window

## Contributing

Issues and pull requests are welcome to help improve this plugin!

## License

MIT
