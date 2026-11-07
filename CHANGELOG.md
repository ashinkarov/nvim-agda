# Changelog

## Unreleased

### Changed

- The plugin no longer needs the `lua-utf8` library; it only needs
  Neovim 0.11 or newer.
- Messages from Agda no longer ask to press ENTER.  Long messages are
  shown as their first line with a hint; the full text is in
  `:messages`.  With the new message UI (`ui2`, Neovim 0.12) messages
  are shown whole.
- Normal forms and helper functions are copied to the system clipboard
  (or to the unnamed register if there is no clipboard provider).
- Goals and unsolved metas are highlighted with the new `AgdaHole` and
  `AgdaUnsolvedMeta` (linked to `AgdaHole`) groups instead of `Todo`,
  which the plugin no longer changes for all filetypes.  The plugin's
  groups are defaults that colour schemes and users can override, and they
  survive `:colorscheme`.
- The commands are defined for Agda buffers only.
- The key mappings are non-recursive and `<nowait>`: they no longer
  wait `'timeoutlen'` when a global mapping starts with the same keys
  (which made moving between goals slow), but such global mappings are
  not reachable in Agda buffers.
- `\bx` inserts `⊠`, as in Agda's Emacs mode; `𝕩` is `\bsx`.
- The file is reloaded after a case split, like in the Emacs mode.

### Added

- A failed load moves the cursor to the error, like the Emacs mode
  (errors in other files are only reported).
- `\^0`…`\^9`, `\^-`, `\^+`, `\^=`, `\^(` and `\^)` insert superscripts.
- `'commentstring'` and `'comments'` are set for Agda's comments, so
  Neovim's `gc` and commenting plugins work (#6).
- `:AgdaStop` stops the Agda process.
- A test suite (`make test`, `make test-live`, `make record`) that
  replays recorded Agda sessions, so it needs no Agda; see
  `tests/README.md`.
- A configuration for the Lua language server (`.luarc.json`).
- `doc/make-case.md` describes the problems of case splitting and a
  proposed fix in Agda.

### Fixed

#### Communication with Agda

- The plugin stopped reacting to Agda until Neovim was restarted when
  a chunk of output ended inside the `JSON> ` prompt or Agda printed a
  line that is not json.  Agda's output is now read line by line;
  other lines are reported and do not affect later messages.
- Strings in commands are quoted as Haskell string literals, which is
  what Agda expects: goal contents with control characters and file
  paths containing `"` or `\` were rejected.
- The module contents command was missing a space.
- `agda --version` is run without a shell (paths with spaces work),
  failures to start Agda are reported, and Agda 3.x is no longer
  treated as older than 2.7.
- When Agda exits, the exit is reported and the next command starts a
  new Agda; before, every command failed until Neovim was restarted.
  The end of Agda's stderr is no longer reported as an empty error.
- The Agda process is stopped when its buffer is reloaded (`:edit`) or
  unloaded, rather than left running.
- After a failed reload, goal commands no longer report "an operation
  on the goal in progress" until Agda is restarted.

#### Goals

- Goals after wide or composing characters (`pick 名前 y = ?`) were not
  found under the cursor, as the column was counted in screen cells
  rather than code points.
- Give, refine, solve and auto edit the Agda buffer directly, so they
  work when another window is current, user mappings do not interfere,
  several goals on one line are filled correctly, and multi-line
  results are indented to the column of the goal.
- Case splitting keeps the indentation of the clause (e.g. inside a
  module) and handles extended lambdas (`λ { … ; … }` and `λ where`)
  like the Emacs mode.  Clauses whose left-hand side or right-hand side
  spans several lines are still not handled; see `doc/make-case.md`.
- Moving between goals follows the order of the file and no longer
  fails once goal 0 has been filled, or after a case split.

#### Windows and highlighting

- Popups are placed at the goal also after wide characters, with a
  number column and with folds, and work in windows created after the
  file was loaded (e.g. with `:split`).
- Autocommands and mappings were added again on every load or popup;
  opening the goal-edit window twice leaked a window.
- Message windows are laid out by display width, so contexts with wide
  characters are aligned.
- Highlighting no longer creates duplicate extmarks for ranges that
  Agda sends several times during a load.
