# Agda for neovim

[![asciicast](https://asciinema.org/a/TvNvhve83WWqJsK2TiN9aAeyp.svg)](https://asciinema.org/a/TvNvhve83WWqJsK2TiN9aAeyp)

# Installation

This plugin requires [Neovim 0.11](https://github.com/neovim/neovim/releases)
or later and has no other dependencies.

Use a plugin manager such as [paq](https://github.com/savq/paq-nvim)
and pass the name of this repository:
```lua
paq 'ashinkarov/nvim-agda'
```
Alternatively, you can install the plugin manually as follows:
```sh
$ mkdir -p ~/.local/share/nvim/site/pack/git-plugins/start
$ git clone https://github.com/ashinkarov/nvim-agda.git --depth=1 ~/.local/share/nvim/site/pack/git-plugins/start/nvim-agda
```

## Configuration

The plugin can be configured by defining a global variable named
`g:nvim_agda_settings` of type dictionary.  So far the following options
are supported (I use lua syntax, but you can define this in vimscript too).
```lua
{
  agda : "/usr/local/bin/agda",            -- Location of Agda binary
  agda_args : { "--arg1", "--arg2"  },     -- Default arguments to Agda binary
  debug_p : true                           -- Turn debug prints on or off
}
```
All the fields of the dictionary may be omitted, as well as the
definition of `g:nvim_agda_settings`.  In this case hard-coded
defaults would be used.

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
the goal list. Both `?` and `{! !}` goals are supported, however the latter
is discouraged, as every edit would modify the file and trigger file reload.

### Implemented commands and shortcuts.
Mostly we implement the same commands as agda-mode in emacs.  Several new
commands have to do with management of the popups and goal editing.

| `<LocalLeader>` Key      |  Agda mode Command       |
|:--------:| -------------- |
| l | Load file |
| , | Show type and context |
| d | Infer type |
| r | Refine the goal |
| m | Elaborate and give: fill the goal with its content, checked and simplified (e.g. `not tt` becomes `ff`) |
| c | Case split on a variable(s) |
| n | Compute the goal content or toplevel expression |
| a | Automatically solve a goal (or all goals in the file) |
| s | Automatically solve constraints in a goal (or in all goals in the file) |
| h | Helper function for the goal |
| o | Show the content of the module |
| w | Explain why a name is in scope: the goal's content in a goal, otherwise the name under the cursor (an operator part such as `∧` stands for `_∧_`) |
| ? | Show the goals with their types, and warnings and errors |
| f | Go to the next goal |
| b | Go to the previous goal |


| `<LocalLeader>` Key      |  Agda mode Command       |
|:--------:| -------------- |
| q | Close the message box |
| e | Edit the goal content |

Within the goal-edit window, `q` is mapped to close the window.
The regular `:q` command would work as well.

`:ShowImplicit` and `:HideImplicit` show or hide implicit arguments,
and `:ShowIrrelevant` and `:HideIrrelevant` irrelevant ones; the choice
lasts across reloads.

Outside goals, why in scope, infer and compute work in the scope at the
top level of the file, as in the Emacs mode: names that a nested module
opens or imports are not in scope there.  To ask in the scope of a
place inside a module, put a goal (`?`) there and use the command in
the goal.

### Going to definitions
After the file has been loaded, `CTRL-]` jumps to the definition of the
name under the cursor, also in other files such as imported modules or
the standard library, and `CTRL-T` jumps back, as with tags (the plugin
sets `'tagfunc'`).  `CTRL-W ]` opens the definition in a new window,
and with the mouse, `CTRL-LeftMouse` and `g<LeftMouse>` jump to the
definition of the name clicked on.
The definitions come from Agda's highlighting, as in the Emacs mode
(`M-.`), so they are those of the last load; names added since then are
not found.

### Highlighting
Agda's highlighting uses the standard highlight groups (`Keyword`,
`Type`, ...) and groups of its own, which you can set in your colour
scheme or configuration:

| Group | Highlights | Default |
|:-----:| ---------- | ------- |
| `AgdaHole` | Goals | dark grey background |
| `AgdaUnsolvedMeta` | Unsolved metas | `AgdaHole` |
| `AgdaUnsolvedConstraint` | Unsolved constraints | `AgdaUnsolvedMeta` |
| `NonTerminating` | Termination problems | red background |
| `NoDefinition` | Missing definitions | blue background |
| `AgdaCoverageProblem` | Missing cases | `DiagnosticUnderlineWarn` |
| `AgdaIncompletePattern` | Incomplete patterns | `DiagnosticUnderlineWarn` |
| `AgdaPositivityProblem` | Positivity problems | `DiagnosticUnderlineWarn` |
| `AgdaInstanceProblem` | Instance problems | `DiagnosticUnderlineWarn` |
| `AgdaConfluenceProblem` | Confluence problems | `DiagnosticUnderlineWarn` |
| `AgdaErrorWarning` | Warnings that are errors | `DiagnosticUnderlineError` |
| `AgdaShadowingInTelescope` | Shadowed names in telescopes | `DiagnosticUnderlineHint` |
| `AgdaCosmeticProblem` | Cosmetic problems | `DiagnosticUnderlineHint` |
| `AgdaDeadcode` | Unreachable clauses | `DiagnosticUnnecessary` |

Problems are highlighted on top of the highlighting of names, so that
for example a name keeps its colour in a clause with missing cases.

### Missing functionality
Compared with the Emacs mode, the plugin does not yet have search
about, the goal type alone or with the checked type, aborting a command,
compiling, or backend commands.  The
normalisation and compute modes are fixed (Emacs chooses them with a
prefix argument), the messages that Agda attaches to highlighted ranges
(such as errors) are not shown, and typing an input sequence such as
`\alpha` gives no feedback until it is complete.  See
[doc/missing.md](doc/missing.md) for the full list.

# Development

`make test` runs the test-suite; see [tests/README.md](tests/README.md).

# Credit
  * https://github.com/coot/vim-agda-integration
  * https://github.com/derekelkins/agda-vim
