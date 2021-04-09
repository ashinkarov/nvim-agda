# Agda for neovim

[![asciicast](https://asciinema.org/a/TvNvhve83WWqJsK2TiN9aAeyp.svg)](https://asciinema.org/a/TvNvhve83WWqJsK2TiN9aAeyp)

# Installation

1. Install [lua-utf8](https://github.com/starwing/luautf8) library on your system.

2. Use a plugin manager such as [paq](https://github.com/savq/paq-nvim) 
   and pass the name of this repository:
   ```lua
   paq 'ashinkarov/nvim-agda'
   ```
   Alternatively, you can clone install the plugin manually as follows:
   ```sh
   $ mkdir -p ~/.local/share/nvim/site/pack/git-plugins/start
   $ git clone https://github.com/ashinkarov/nvim-agda.git --depth=1 ~/.local/share/nvim/site/pack/git-plugins/start/nvim-agda
   ```

# Details

NeoVim comes with built-in lua support which dramatically simplifies development of complex plugins.
While currently the plugin is in its infancy, it is a reasonable proof of concept.

## Design principles
  * Use asynchronous communication so that we can use the editor when Agda is working.
  * Avoid goal commands when the file has not been typechecked.
  * Use popup windows to show location-specific information.
  * Don't treat Agda as a black box; change the way it interacts in case it makses sense.
  * Try to be efficient.

## Status

The main functionality including communication with Agda process, basic utf8 input, and basic commands seem to work.
Goal specific information such as context, goal type, etc. is shown in a window located right below the goal.
The goal content is edited in a separate window, so that it does not alter the state of the file.  If a goal
action is performed on a modified file, the file is reloaded first and the goal list is synchronised.  Both
`?`-goals and `{! !}` goals are supported, however editing goal content in a separate window makes the latter
redundant.

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
| q | Close the message box |
| e | Edit the goal content |


### Todo
  * Implement remaining commands from the original `agda-mode`
  * Support working with multiple files.  Currently we only support a single file per vim instance.
  * If a goal action is triggered on a modified buffer, we first issue reload command, and turn the action into
    continuation that is handled when the list of goals is updated.  Ensure that this is "thread safe".
  * Asynchronous communication quirks:
    - Hilighting information uses offsets (number of characters from the beginning of file), whereas nvim interface expects
      line and byte-offset in that line to set the hilighting.  This is important as this conversion is expensive and it
      pulls `lua-utf8` as a dependency.
    - Errors are printed on stdout (not stderr)
    - Agda doesn't seem to flush the buffer after outputting the command, so buffered read does not work.  As a consequence
      one needs to track whether we received enough bytes that can be parsed as a valid json.  Current implementation is hacky.
  * If highlighting information arrives, but the file is modified --- should we attempt to colorise all but modified pieces?
    This is happening on big Agda files.
  * Inputing utf8 symbols.  Currently we define a bunch of shortcuts, so there is no visual response when one is typing `\alpha`.
    Should we implement a [which-key](https://github.com/liuchengxu/vim-which-key) for the insert mode?

# Credit
  * https://github.com/coot/vim-agda-integration
  * https://github.com/derekelkins/agda-vim
