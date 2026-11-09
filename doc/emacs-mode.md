# The plugin compared with the Emacs mode

How the features of Agda's Emacs mode (`src/data/emacs-mode` in Agda
2.8.0) map to this plugin, with the reasons for the differences.  Keys
are `<LocalLeader>` mappings in Agda buffers (`\` by default).  Each
entry starts with one of

* **Works**: the plugin has it;
* **Missing**: not done yet;
* **Won't implement**: decided against, with the reason.

What changed when is in [CHANGELOG.md](../CHANGELOG.md).

## Commands

| Emacs command | Emacs key | Plugin |
|---|---|---|
| Load | `C-c C-l` | **Works:** `\l`, `:AgdaLoad`.  Saves the buffer, and reloads it first if the file changed on disk. |
| Compile | `C-c C-x C-c` | **Missing:** `Cmd_compile`; needs a choice of backend and a handler for `CompilationOk`. |
| Backend interaction | `C-c C-i` | **Missing:** `Cmd_backend_top`, `Cmd_backend_hole`. |
| Quit | `C-c C-x C-q` | **Works:** `:AgdaStop`. |
| Restart | `C-c C-x C-r` | **Won't implement:** `:AgdaStop` followed by `\l` (or any command) does the same, e.g. for an Agda that is stuck or after upgrading it; a command would only save a step. |
| Abort | `C-c C-x C-a` | **Won't implement (for now):** after `Cmd_abort` Agda goes back to the state it keeps across loads (`maybeAbort` in `Interaction/InteractionTop.hs`), so the loaded file and its goals are gone and the file has to be loaded again, as after `:AgdaStop`.  Abort only keeps the imported modules in memory, whereas a new Agda reads them from their `.agdai` files. |
| Remove annotations | `C-c C-x C-d` | **Won't implement:** in Emacs goals are overlays that get in the way of editing, and this turns them back into text and removes the highlighting.  Here goals are plain text and highlighting is only colour, and misplaced highlighting after edits is better fixed by reloading. |
| Toggle implicit arguments | `C-c C-x C-h` | **Works:** `:ShowImplicit`, `:HideImplicit`.  Unlike in Emacs, the choice lasts across reloads. |
| Toggle irrelevant arguments | `C-c C-x C-i` | **Works:** `:ShowIrrelevant`, `:HideIrrelevant`, also lasting across reloads. |
| Show constraints | `C-c C-=` | **Works:** `:AgdaShowConstraints` (no key). |
| Solve constraints | `C-c C-s` | **Works:** `\s`, in a goal or for all goals. |
| Show goals | `C-c C-?` | **Works:** `\?`, `:PrintGoals`: goals, warnings and errors as after a load. |
| Next and previous goal | `C-c C-f`, `C-c C-b` | **Works:** `\f`, `\b`. |
| Give | `C-c C-SPC` | **Works, differently:** give through refine: `\r` on a goal with content, or `\e` to edit the goal in a window and `\r` there.  Refine (`Cmd_refine_or_intro`) gives the expression when it fits the goal. |
| Give with force | `C-u C-c C-SPC` | **Won't implement:** force (`WithForce`) only skips two checks after the term is put into the goal (`give_` in `Interaction/BasicOps.hs`): re-running the termination check of the surrounding function, whose failure is only a warning and which the next load does anyway, and a double check with the internal type checker, a safety net that should not fail for a term that was just checked.  It does not let one give ill-typed terms. |
| Elaborate and give | `C-c C-m` | **Works:** `\m`, `:AgdaElaborateGive`, with `Simplified` (the Emacs default): `not tt` becomes `ff`. |
| Refine | `C-c C-r` | **Works:** `\r`; an empty goal of function type gets `λ x → ?`, and with `\1r` the pattern-matching lambda `λ { x → ? }` (Emacs: with a prefix argument). |
| Auto | `C-c C-a` | **Works:** `\a`, in a goal or for all goals. |
| Case split | `C-c C-c` | **Works, with limits:** `\c`.  Like in Emacs, clauses are assumed to be on the lines of the goal; clauses whose left- or right-hand side spans several lines are not replaced properly.  See [make-case.md](make-case.md) for a fix in Agda. |
| Goal type | `C-c C-t` | **Won't implement:** only the goal type, without the context; `\,` shows both, and the type comes first. |
| Context | `C-c C-e` | **Works:** `:AgdaContext` (no key: `\e` edits the goal).  Shadowed names are shown as Agda prints them (`x₁`), and names that are not in scope are marked; Emacs also shows `x = x₁` when the original name is in scope, which the json does not say. |
| Helper function type | `C-c C-h` | **Works:** `\h`; the type is also copied to the clipboard. |
| Infer type | `C-c C-d` | **Works:** `\d`, in a goal or for an expression asked for. |
| Why in scope | `C-c C-w` | **Works:** `\w`.  In a goal, for its content; otherwise for the name under the cursor, found in Agda's highlighting, with operator parts completed (`∧` asks about `_∧_`; for operators renamed on import this gives the old name), or for a name asked for. |
| Goal type and context | `C-c C-,` | **Works:** `\,` (`\5,` or `\u,` normalised), followed by the constraints that mention the goal. |
| Goal type, context and inferred type | `C-c C-.` | **Works:** `\.`. |
| Goal type, context and checked type | `C-c C-;` | **Won't implement:** like `\.`, but shows the goal's content checked against the goal type and normalised instead of its type, i.e. what elaborate and give (`\m`) would put in; `\m` and `\n` cover this. |
| Search about | `C-c C-z` | **Works:** `\z`, `:AgdaSearchAbout`.  Like in Emacs, the input is a list of names that the types must mention and `"quoted"` parts of the definitions' names (e.g. `ℕ _+_ "comm"`); it is not a search by type, so `ℕ → ℕ` gives a parse error (`→` is not a name). |
| Module contents | `C-c C-o` | **Works:** `\o`.  In a goal, for the module named by its content; an empty name stands for the current module.  Types are shown below the names, as long names would push aligned types far to the right. |
| Compute normal form | `C-c C-n` | **Works:** `\n`, and `\1n` to `\3n` for the other compute modes (see below); the normal form is also copied to the clipboard. |
| Version | | **Works:** `:AgdaVersion`. |
| Switch Agda version | `C-c C-x C-s` | **Works, differently:** the binary is set in `g:nvim_agda_settings`. |
| Describe character | | **Works, by Neovim:** `ga` shows the character's code; the input sequence is not shown. |
| Comment the rest of the buffer | `C-c C-x M-;` | **Works, by Neovim:** `gcG`, with the `'commentstring'` that the plugin sets (`gc` comments in general). |
| Indentation cycling | `TAB` | **Missing:** Neovim's own indentation applies. |
| Go to definition | `M-.` | **Works:** `CTRL-]` (and `CTRL-W ]`), through `'tagfunc'`. |
| Go to definition with the mouse | `mouse-2` | **Works, by Neovim:** `CTRL-LeftMouse` and `g<LeftMouse>` do `CTRL-]` at the click. |
| Go back | `M-,` | **Works:** `CTRL-T`, through the tag stack. |
| Input method | `\` sequences | **Works, differently:** insert-mode mappings (`agda-input.vim`).  Neovim shows the keys typed so far; the candidates (which Emacs shows) only with a plugin such as which-key.nvim or mini.clue (see the README).  **Missing:** some sequences are defined twice. |

Commands the plugin has that the Emacs mode does not: `\e` edits the
goal's content in a window, where the goal commands work on it; `\q`
closes the popup.

## Arguments

* **Normalisation** (`AsIs`, `Instantiated`, `HeadNormal`, `Simplified`,
  `Normalised`): **Works, differently.**  The Emacs mode chooses with
  the prefix argument (none, `C-u`, `C-u C-u`, other), and which level
  each prefix stands for differs between commands.  The plugin numbers
  the levels in Agda's order, from `\1` (`AsIs`) to `\5` (`Normalised`),
  for every command that takes one (`\5,`, `:AgdaInfer 5`); without a
  number each command has a default: context `HeadNormal`, infer
  `Normalised`, helper function and auto `AsIs`, the others
  `Simplified` (without a prefix the Emacs mode uses `Simplified`, or
  `AsIs` for the helper function and auto).
* **Compute mode**: **Works.**  `DefaultCompute` without a number, and
  as in the Emacs mode's order of prefixes, `\1n` `IgnoreAbstract`,
  `\2n` `UseShowInstance` and `\3n` `HeadCompute`.
* **Ranges**: **Won't implement.**  All goal commands send `noRange`;
  the Emacs mode sends the goal's range when the input comes from the
  goal.  Agda uses the range for three things: as the position where
  parsing the goal's text starts, so that errors in the text point into
  the file; as the new position of the goal; and for give and refine,
  to tell the editor to keep the text as written when Agda does not
  change it (`GiveAction` with `paren` rather than `str`).  The plugin
  reloads the file before the next goal command when the buffer changed
  (e.g. after give or refine) or a command failed, and right after a
  case split, which recomputes all positions; errors in a goal's text only give positions
  counted from the start of the text.  So the only difference left is
  that given expressions are replaced by Agda's printing of them (e.g.
  `λ x → x` for `\x -> x`).
* **Load options**: `Cmd_load` gets only `--show-implicit` and
  `--show-irrelevant` (when set).  The Emacs mode passes the user's
  `agda2-program-args` there; the plugin passes `agda_args` (see the
  README) on Agda's command line instead.
* **Highlighting**: commands ask for `Interactive` highlighting sent
  `Direct`ly, which is what an editor needs.

Commands of the interface that neither the plugin nor the Emacs mode
uses interactively: `Cmd_load_no_metas`, `Cmd_highlight`,
`Cmd_tokenHighlighting`, `Cmd_load_highlighting_info`, `Cmd_intro`
(refine uses it for empty goals), `ToggleImplicitArgs`.

## Information from Agda that is not shown

* **Status** (whether the file is checked, whether implicit and
  irrelevant arguments are shown): **Works, differently.**  The Emacs
  mode shows it in the mode line; the plugin puts it, with whether Agda
  is busy and the number of goals, in `b:agda_status` for the user's
  status line (see the README).
* **Messages on highlighted ranges** (`note`, e.g. the text of the error
  at its range): **Works, differently.**  The Emacs mode shows them when
  the mouse is over the range.  Agda attaches messages only to the
  error, so the plugin instead makes Neovim diagnostics of the error,
  the warnings and the unsolved metas, from their messages (which start
  with the place) and ranges (see "Diagnostics" in the README).
  **Missing (for the future):** unsolved constraints, as Agda does not
  send where they are (see [agda-upstream.md](agda-upstream.md)); their
  places are highlighted (`AgdaUnsolvedConstraint`), but without text,
  and with several constraints the two cannot be matched.
* **Highlighting details**: `remove` and `tokenBased`, and `tokenBased`
  of `ClearHighlighting`.  The plugin never removes highlighting for a
  range and clears all of it, whereas Agda distinguishes token-based
  highlighting.
* **Goal type and context**: `rewrite` (the level that was asked for).
* **Constraints**: `problems` and `unblocker` (what a constraint is
  blocked on).
* **Smaller things**: the `debugLevel` of `RunningInfo`; `time`,
  `commandState` and `computeMode` of normal forms and inferred types;
  the `filepath` of why in scope.
* **Context entries**: the plugin shows everything the json has, which
  is less than the Emacs mode shows (see
  [agda-upstream.md](agda-upstream.md)).
* Responses for commands the plugin does not send (`Mimer`,
  `DoneAborting`, `DoneExiting`, `CompilationOk`, `Time`, the
  goal-specific `CurrentGoal` and `GoalAndElaboration`) are reported as
  information the plugin cannot show, if they arrive.

## Other differences

* **Messages** go to Neovim's message area without the hit-enter prompt
  (the full text is in `:messages`), where the Emacs mode uses an
  `*Agda information*` buffer.  Results such as the context, types and
  normal forms are shown in a popup at the goal.
* **Scope outside goals**: why in scope, search about, infer and compute
  use the scope at the top level of the file, as in the Emacs mode, so
  names that a nested module opens are not in scope there.  Asking in a
  goal uses the goal's scope.  See [agda-upstream.md](agda-upstream.md).
* **Highlighting after edits**: **Works.**  When Agda's highlighting
  arrives after the buffer was edited (during a long load), its
  positions refer to the text that Agda loaded.  The plugin compares
  that text with the buffer: lines that were not edited get their
  highlighting where they are now, edited lines keep their old
  highlighting, and a warning says how many places were not updated.
  The same goes for jumping to an error and to definitions.  (Goals
  found in a load still refer to the loaded text.)
