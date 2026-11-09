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
With [lazy.nvim](https://github.com/folke/lazy.nvim), add this to your
plugin specs (`ft` and `init` are optional):
```lua
{
  "ashinkarov/nvim-agda",
  ft = "agda",     -- load the plugin when an Agda file is opened
  init = function()
    -- Settings (see Configuration) must be set before the plugin loads.
    vim.g.nvim_agda_settings = { agda = "/path/to/agda" }
  end,
}
```
With `ft = "agda"` the plugin is loaded for `.agda`, `.lagda` and
`.lagda.md` files.
Alternatively, you can install the plugin manually as follows:
```sh
$ mkdir -p ~/.local/share/nvim/site/pack/git-plugins/start
$ git clone https://github.com/ashinkarov/nvim-agda.git --depth=1 ~/.local/share/nvim/site/pack/git-plugins/start/nvim-agda
```

## Versions

The plugin follows [semantic versioning](https://semver.org); releases
are tagged `vX.Y.Z` and their changes are listed in
[CHANGELOG.md](CHANGELOG.md).  `:AgdaVersion` shows the version you
have.  The plugin managers install master by default; to install the
latest release instead, add `version = "*"` to the lazy.nvim spec, or
clone with `--branch vX.Y.Z`.

## Configuration

The plugin is configured with the global dictionary
`g:nvim_agda_settings`, for example in Lua:
```lua
vim.g.nvim_agda_settings = {
  agda = "/usr/local/bin/agda",      -- the Agda binary (default: agda)
  agda_args = { "--arg1", "--arg2" },  -- arguments to pass to Agda
  diagnostics = "all",               -- "all", "structured" or "none" (see Diagnostics)
  diagnostic_severity = { MissingDefinitions = false },  -- (see Diagnostics)
  debug_p = true,                    -- print debug messages
}
```
or in Vimscript, `let g:nvim_agda_settings = {'agda': '/usr/local/bin/agda'}`.
Every entry may be omitted, as may the variable itself.  The settings
are read when an Agda buffer is opened.

# Details

[Neovim](https://neovim.io/) comes with built-in [Lua](https://www.lua.org/)
support, which makes it much simpler to write complex plugins.  This
plugin is written almost entirely in Lua, which handles the asynchronous
interaction with Agda and the state of the editor.

## Design principles
  * Use asynchronous communication so that we can use the editor when Agda is working.
  * Avoid goal commands when the file has not been typechecked.
  * Use popup windows to show location-specific information.
  * Don't treat Agda as a black box; change the way it interacts in case it makes sense.
  * Try to be efficient.

## Status

The plugin covers most of the interaction of Agda's Emacs mode: loading
and highlighting, the goal commands, case splitting, going to
definitions and the input of Unicode characters.  It does not try to
copy the Emacs mode exactly; [doc/emacs-mode.md](doc/emacs-mode.md)
compares the two command by command, with what is missing, what works
differently and what we decided against.

Information about a goal (its type and context, inferred types, normal
forms) is shown in a popup at the goal; other messages go to the
message area, with the full text in `:messages`.  The content of a goal
can be edited in a separate window (`\e`), so that the file does not
change, and the goal commands work there too.  Goal commands on a file
that was changed reload it first, so that the goals are up to date.
Both `?` and `{! !}` goals work; typing into a `{! !}` goal changes the
file, so the next goal command reloads it.

### Commands and keys
The keys are `<LocalLeader>` mappings (`\` by default) in Agda buffers.

| Key | Command | What it does |
|:---:| ------- | ------------ |
| l | `:AgdaLoad` | Load (type-check) the file |
| , | `:AgdaTypeContext` | Show the goal type and context, and the constraints on the goal |
| . | `:AgdaTypeContextInfer` | The same, with the type of the goal's content |
| d | `:AgdaInfer` | Infer the type of the goal's content, or of an expression |
| n | `:AgdaCompute` | Compute the normal form of the goal's content, or of an expression (also copied to the clipboard) |
| r | `:AgdaRefine` | Refine the goal: give its content if it fits, otherwise apply it, or introduce a constructor or lambda in an empty goal |
| m | `:AgdaElaborateGive` | Elaborate and give: fill the goal with its content, checked and simplified (e.g. `not tt` becomes `ff`) |
| c | `:AgdaMakeCase` | Case split on the variables in the goal |
| a | `:AgdaAuto` | Search for a solution of the goal (or of all goals in the file) |
| s | `:AgdaSolve` | Solve the constraints of the goal (or of all goals in the file) |
| h | `:AgdaHelperFun` | Show the type of a helper function for the goal's content (also copied to the clipboard) |
| o | `:AgdaModuleContents` | Show the contents of a module |
| w | `:AgdaWhyInscope` | Explain why a name is in scope: the goal's content in a goal, otherwise the name under the cursor (an operator part such as `∧` stands for `_∧_`) |
| z | `:AgdaSearchAbout` | Search about: the definitions whose types mention all the given names, and whose names contain the given `"quoted"` parts (e.g. `ℕ _+_ "comm"`); not a search by type |
| ? | `:PrintGoals` | Show the goals with their types, and the warnings and errors |
| f | `:GoalNext` | Go to the next goal |
| b | `:GoalPrev` | Go to the previous goal |
| e | `:MkPrompt` | Edit the goal's content in a window |
| q | `:AgdaCloseMsg` | Close the popup |

In the goal-edit window, the keys `, . d n r m c a s h` work on the
goal with the content of the window, `\q` closes the popup and `q`
closes the window (as does `:q`).

Commands without keys: `:AgdaContext` (the context of the goal alone),
`:AgdaShowConstraints`, `:ShowImplicit` and `:HideImplicit`,
`:ShowIrrelevant` and `:HideIrrelevant` (show or hide implicit or
irrelevant arguments; the choice lasts across reloads), `:AgdaVersion`
(the versions of the plugin and of Agda),
and `:AgdaStart` and `:AgdaStop` (start or stop the Agda process; any
command starts it when needed).

Outside goals, why in scope, search about, module contents, infer and
compute work in the scope at the top level of the file, as in the Emacs
mode: names that a nested module opens or imports are not in scope
there.  To ask in the scope of a place inside a module, put a goal (`?`)
there and use the command in the goal.

### Normalisation and modes
A number between `<LocalLeader>` and the key chooses how far Agda
normalises what it shows: `\1,` as is, `\2,` instantiated, `\3,` head
normal form, `\4,` simplified and `\5,` normalised.  This works for
`, . d m a s h o z ?` (also in the goal-edit window) and for
`:AgdaContext`; the commands take the number as an argument, as in
`:AgdaInfer 5`.  Without a number each command uses its default:
simplified, except for the context (head normal form), infer
(normalised), and helper functions and auto (as is).  `\u,` is the same
as `\5,`.

For compute (`n`) the number chooses the mode instead: `\1n` ignores
`abstract`, `\2n` uses the `Show` instance of the type to print the
result, and `\3n` computes only the head normal form.  `\1r` refines an
empty goal of function type with a pattern-matching lambda
(`λ { x → ? }`) rather than `λ x → ?`.

### Diagnostics
After a load, the error, the warnings (termination and coverage
problems, unreachable clauses, ...) and the unsolved metas are also
Neovim diagnostics, with Agda's message.  `CTRL-W d` shows the message
at the cursor, `]d` and `[d` go to the next and previous one, and
`:lua vim.diagnostic.setloclist()` lists them.  They are not underlined,
as the highlighting marks these places already; virtual text and signs
follow your `vim.diagnostic.config()`.  Unsolved constraints have no
diagnostics, as Agda does not say where they are.  Where a line has
several diagnostics, its sign is that of the most severe one.

The diagnostics have Agda's level, error or warning, except missing
definitions: Agda reports them as errors, but they are hints, as a
module being written usually has some.  The setting
`diagnostic_severity` sets the severity by the name of the warning,
`"error"`, `"warn"`, `"info"`, `"hint"`, or `false` for no diagnostic:
```lua
vim.g.nvim_agda_settings = {
  diagnostic_severity = { MissingDefinitions = false, UnsolvedMeta = "hint" },
}
```
The names are those in Agda's messages, e.g. `[CoverageIssue]` or
`-W[no]UnreachableClauses`, which are also the diagnostics' codes;
`agda --help=warning` lists them.  Unsolved metas are `UnsolvedMeta`.
The error that stops a load has no name and is always an error.
Anything else that depends on the severity is set with Neovim's
`vim.diagnostic.config()` for the plugin's namespace, for example to
show signs only for warnings and errors:
```lua
vim.diagnostic.config({ signs = { severity = { min = vim.diagnostic.severity.WARN } } },
                      require("agda.diagnostics").ns)
```

Agda sends the places of the error and of unsolved metas as data, but
those of warnings only at the start of their messages, in a format that
may change.  If the diagnostics of warnings ever go wrong, set
`diagnostics` to `"structured"` in `g:nvim_agda_settings` to keep only
the error and unsolved metas, or to `"none"` for no diagnostics.
The names of warnings come from their messages too, so with
`"structured"` only `UnsolvedMeta` in `diagnostic_severity` applies.

### Typing Unicode
In insert and command-line mode, `<LocalLeader>` (`\` by default)
starts an input sequence, many of them as in the Emacs mode: `\to`
gives `→`, `\ga` `α`, `\bN` `ℕ`, `\McC` `𝒞`, `\1` `₁`; see
`lua/agda/input.lua` for the full list.  In other buffers,
`:runtime agda-input.vim` sets them too.
On the command line, where some sequences are also Vim's regex syntax
(`\<`, `\.`, `\1`, ...), type `CTRL-V` before the backslash to get the
backslash itself: `/` `CTRL-V` `\<foo` searches for `\<foo`.
While you type a sequence Neovim shows the keys typed so far, but not
how the sequence can continue.  A plugin that shows the possible
continuations of a mapping can do that, as the sequences are ordinary
buffer-local mappings.  We have not tried these, but they should work:

* [which-key.nvim](https://github.com/folke/which-key.nvim): its
  automatic triggers include insert mode, so after `\` it lists the next
  keys with the characters they give.
* [mini.clue](https://github.com/nvim-mini/mini.nvim) needs a trigger
  for `<LocalLeader>` in insert mode:
  ```lua
  require('mini.clue').setup({ triggers = { { mode = 'i', keys = '<LocalLeader>' } } })
  ```

### Status line
The plugin does not change your status line, but keeps a short
description of what Agda is doing in `b:agda_status`, e.g.
`Agda: checking…`, `Agda: 2 goals`, `Agda: checked` (no goals or
unsolved metas left) or `Agda: error`, followed by `(implicit)` or
`(irrelevant)` when those arguments are shown.  It is empty in other
buffers and when Agda is not running.  To show it, add `AgdaStatus()`
to your status line:
```vim
set statusline+=%{AgdaStatus()}
```
With a statusline plugin, use a component that returns
`vim.b.agda_status`, e.g. for lualine:
```lua
sections = { lualine_x = { function() return vim.b.agda_status or "" end } }
```
The `User AgdaStatus` autocommand runs whenever the status changes, for
status lines that need to be told to refresh.

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
`Type`, ...) and groups of its own.  By default these are links to
standard groups, so that they take their colours from your colour
scheme: goals have the background of `DiffAdd` (greenish in most colour
schemes), and problems are underlined like diagnostics.

| Group | Highlights | Default |
|:-----:| ---------- | ------- |
| `AgdaHole` | Goals | `DiffAdd` |
| `AgdaUnsolvedMeta` | Unsolved metas | `DiagnosticUnderlineWarn` |
| `AgdaUnsolvedConstraint` | Unsolved constraints | `AgdaUnsolvedMeta` |
| `NonTerminating` | Termination problems | `DiagnosticUnderlineWarn` |
| `NoDefinition` | Missing definitions | `DiagnosticUnderlineWarn` |
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

You can set the groups in your colour scheme or configuration.
`:colorscheme` clears them, so set them after it, or in a `ColorScheme`
autocommand:
```lua
vim.api.nvim_create_autocmd("ColorScheme", {
  callback = function()
    vim.api.nvim_set_hl(0, "NonTerminating", { bg = "#5f2f2f" })
  end,
})
```
Some colour schemes have an option for this.  With
[catppuccin](https://github.com/catppuccin/nvim), `custom_highlights`
sets groups with the colours of the flavour in use:
```lua
require("catppuccin").setup({
  custom_highlights = function(colors)
    return {
      AgdaHole = { bg = colors.surface1 },
      NonTerminating = { bg = colors.maroon, fg = colors.base },
      NoDefinition = { sp = colors.peach, undercurl = true },
    }
  end,
})
```

If you edit the file while Agda checks it, the highlighting that
arrives afterwards is applied to the lines that you did not edit, and a
warning says how many places were left out until the next load.

### Missing functionality
Compared with the Emacs mode, the plugin does not have aborting a
command (use `:AgdaStop`, which has the same effect), compiling, or
backend commands.  Unsolved constraints are not shown at their places
(see "Diagnostics"), and while typing an input sequence such as `\ga`
the possible continuations are shown only with a plugin (see "Typing
Unicode").  See [doc/emacs-mode.md](doc/emacs-mode.md) for a comparison
with the Emacs mode.

# Development

`make test` runs the test-suite; see [tests/README.md](tests/README.md).
GitHub runs it for every pull request.

Changes are listed under "Unreleased" in CHANGELOG.md.  To release them
as version X.Y.Z, run `make release VERSION=X.Y.Z` on master (see
[scripts/release.sh](scripts/release.sh)): it gives the section the
version and the date, sets `M.version` in `lua/agda/init.lua`, runs the
tests, commits, and tags the commit `vX.Y.Z` with the section as the
message of the tag (for the release notes).  Then push the commit and
the tag with `git push origin master vX.Y.Z`.

# Credit
  * https://github.com/coot/vim-agda-integration
  * https://github.com/derekelkins/agda-vim
