# Agda for neovim

[![asciicast](https://asciinema.org/a/TvNvhve83WWqJsK2TiN9aAeyp.svg)](https://asciinema.org/a/TvNvhve83WWqJsK2TiN9aAeyp)

# Installation

1. Install [lua-utf8](https://github.com/starwing/luautf8) library on your system.

2. Use a plugin manager such as [paq](https://github.com/savq/paq-nvim)
   and pass the name of this repository:
   ```lua
   paq 'ashinkarov/nvim-agda'
   ```
   Alternatively, you can install the plugin manually as follows:
   ```sh
   $ mkdir -p ~/.local/share/nvim/site/pack/git-plugins/start
   $ git clone https://github.com/ashinkarov/nvim-agda.git --depth=1 ~/.local/share/nvim/site/pack/git-plugins/start/nvim-agda
   ```

# Details

[NeoVim](https://neovim.io/) comes with built-in [Lua](https://www.lua.org/) support
which dramatically simplifies development of complex plugins.  This plugin is written
almost entirely in Lua, which handles asynchronous interaction and editor state
manipulation.

## Design principles
  * Use asynchronous communication so that we can use the editor when Agda is working.
  * Avoid goal commands when the file has not been typechecked.
  * Use popup windows to show location-specific information.
  * Don't treat Agda as a black box; change the way it interacts in case it makses sense.
  * Try to be efficient.

## Status

Minimal functionality including communication with Agda process, basic utf8
input, and basic commands are implemented.  Goal specific information such as
context, goal type, etc. is shown in a popup window appearing at the goal location.
The goal content is edited in a separate window, so that it does not alter the
state of the file.  Goal actions on a modified file reload the file and synchronise
the goal list. Both `?` and `{! !}` goals are supported, however the latters
is discouraged, as every edit would modify the file and trigger file reload.

### Implemented commands and shortcuts.
| `<LocalLeader>` Key      |  Command       |
|:--------:| -------------- |
| l | Load file |
| , | Show type and context |
| d | Infer type |
| r | Refine the goal |
| c | Case split on a variable(s) |
| n | Compute the goal content or toplevel expression |
| a | Automatically look for goal (or all goals in the file) |
| h | Helper function for the goal |
| q | Close the message box |
| e | Edit the goal content |
| ? | Show Goals |
| f | Go to the next goal |
| b | Go to the previous goal |


### Todo
  * Implement remaining commands from the original `agda-mode`
  * Support working with multiple files.  Currently we assume a single
    file per vim instance.
  * Goal actions on a modified buffer reload the file and pospone the
    action via continuation.  Ensure that this is "thread safe" (does not
    have race conditions).
  * Asynchronous communication quirks:
    - Hilighting information uses offsets (number of characters from the
      beginning of file), whereas nvim interface expects line and byte-offset
      in that line to set the hilighting.  This is important as this conversion
      is expensive and it
      pulls `lua-utf8` as a dependency.
    - Errors are printed on stdout (not stderr)
  * If highlighting information arrives, and the file is modified --- should we
    attempt to colorise all but modified pieces?  This is a typical case whe
    happening big files.  Agda is very slow, and it is tempting to edit a few
    things before the colors arrive.
  * Utf-8 input is happening via defining insert mode shortcuts, so there
    is no visual response when one is typing things like `\alpha`.  Should
    we implement a [which-key](https://github.com/liuchengxu/vim-which-key)
    for the insert mode?

# Credit
  * https://github.com/coot/vim-agda-integration
  * https://github.com/derekelkins/agda-vim
