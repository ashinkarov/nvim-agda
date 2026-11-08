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
- `:ShowImplicit` and `:HideImplicit` last until changed; Agda reset the
  choice on every load.
- `\?` (`:PrintGoals`) shows Agda's list of goals with their types, as
  after a load, instead of the positions of the goals.
- Goals are listed like Agda prints them (`?0 : 𝔹`, and invisible goals
  with their position) rather than as `0 OfType 𝔹`.

### Added

- Search about (`\z`, `:AgdaSearchAbout`) lists the definitions whose
  types mention the given names, like `C-c C-z` in the Emacs mode.
- `:AgdaVersion` shows the version of the running Agda.
- `:ShowIrrelevant` and `:HideIrrelevant` show or hide irrelevant
  arguments, and the choice lasts across reloads.
- Elaborate and give (`\m`, `:AgdaElaborateGive`) fills the goal with
  its content checked and simplified, like `C-c C-m` in the Emacs mode.
- `CTRL-]` jumps to the definition of the name under the cursor, and
  `CTRL-T` back (see "Going to definitions" in the README).
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
- `doc/agda-upstream.md` collects other places where Agda's interaction
  interface could be improved.
- `doc/missing.md` lists what the plugin does not do yet compared with
  the Emacs mode and Agda's interface; the README's todo list is gone.

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
- If the file changed on disk, loading it first lets Neovim reload the
  buffer (`:checktime`), so that Agda does not check a different text
  than the buffer shows.
- The Agda process is stopped when its buffer is reloaded (`:edit`) or
  unloaded, rather than left running.
- When a load fails, the warnings found before the error (such as
  termination problems), which Agda sends with the error, are shown;
  they were dropped.
- After a failed reload, goal commands no longer report "an operation
  on the goal in progress" until Agda is restarted.

#### Goals

- `:AgdaShowConstraints` showed nothing, and neither did refine on an
  empty goal when Agda cannot introduce a constructor; both are shown
  now.  Any other information from Agda that the plugin cannot show is
  reported instead of being ignored.

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
- The context showed shadowed variables with their original name, so
  that `x` appeared twice; they are now shown as Agda prints them
  (`x₁`), and names that are not in scope are marked, like in the
  Emacs mode.
- Why in scope asked about the WORD under the cursor, such as `(F.blah`.
  It now takes the name from Agda's highlighting, completing operator
  parts (`∧` becomes `_∧_`, `then` becomes `if_then_else_`); in a goal
  it explains the goal's content in its context, like the Emacs mode,
  and without a name it asks, suggesting the text under the cursor.
  The answer says whether it is for the top level or for a goal.
- Module contents show the submodules, which were left out (a module
  with only submodules looked empty).  An empty module name shows the
  current module, and in a goal the goal's content names the module, in
  the goal's scope.
- Refine on an empty goal of function type introduced a pattern-matching
  lambda (`λ { x → ? }`); it now introduces `λ x → ?`, like the Emacs
  mode.
- Moving between goals follows the order of the file and no longer
  fails once goal 0 has been filled, or after a case split.

#### Windows and highlighting

- Popups are placed at the goal also after wide characters, with a
  number column and with folds, and work in windows created after the
  file was loaded (e.g. with `:split`).
- Autocommands and mappings were added again on every load or popup;
  opening the goal-edit window twice leaked a window.
- Popups wider than the screen are as wide as the screen, with their
  separators drawn to that width and room for the wrapped lines.
- Message windows are laid out by display width, so contexts with wide
  characters are aligned.
- Records, fields, coinductive constructors, macros, pragmas and
  generalizable variables are highlighted, as are coverage, positivity,
  instance and confluence problems, incomplete patterns, unreachable
  clauses and shadowed names, with new groups linked to Neovim's
  diagnostic groups.  Problems are shown on top of the highlighting of
  names.
- Highlighting no longer creates duplicate extmarks for ranges that
  Agda sends several times during a load.
