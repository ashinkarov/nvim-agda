# What the plugin does not do yet

Compared with Agda's Emacs mode and with what Agda's interaction
interface offers (Agda 2.8.0: commands in `Interaction/Base.hs`,
responses in `Interaction/JSONTop.hs`, the Emacs mode in
`src/data/emacs-mode/agda2-mode.el`).  For coming back to later; the
README lists the main missing features.  Items that have been done since
are marked **Implemented**, those we decided against **Won't
implement**.

## Commands

Emacs commands (with their keys) that the plugin does not have:

| Emacs command | Key | Agda command | Notes |
|---|---|---|---|
| Give | `C-c C-SPC` | `Cmd_give` | The plugin gives through refine (`Cmd_refine_or_intro`), which behaves the same when the expression fits the goal. |
| Elaborate and give | `C-c C-m` | `Cmd_elaborate_give` | **Implemented:** `\m`, `:AgdaElaborateGive`, with `Simplified` (the Emacs default). |
| Goal type | `C-c C-t` | `Cmd_goal_type` | Only the goal type, without the context (the plugin has goal type and context). |
| Goal type, context and checked type | `C-c C-;` | `Cmd_goal_type_context_check` | Would also need the `GoalAndElaboration` answer. |
| Search about | `C-c C-z` | `Cmd_search_about_toplevel` | Would also need the `SearchAbout` answer. |
| Show goals | `C-c C-?` | `Cmd_metas` | The plugin's `:PrintGoals` lists the goal positions it knows; Agda's list (with types, as shown after a load) is not requested. |
| Abort | `C-c C-x C-a` | `Cmd_abort` | Stops a running command without stopping Agda; would also need `DoneAborting`. |
| Compile | `C-c C-x C-c` | `Cmd_compile` | Would also need the `CompilationOk` answer. |
| Backend interaction | `C-c C-i` | `Cmd_backend_top`, `Cmd_backend_hole` | |
| Restart | `C-c C-x C-r` | | `:AgdaStop`, then any command starts a new Agda. |
| Remove annotations | `C-c C-x C-d` | | Remove the goals and the highlighting. |
| Toggle irrelevant arguments | `C-c C-x C-i` | `ShowIrrelevantArgs`, `ToggleIrrelevantArgs` | Like `:ShowImplicit` and `:HideImplicit`; the choice would also have to be passed on every load (`--show-irrelevant`). |
| Version | | `Cmd_show_version` | Would also need the `Version` answer. |
| Switch Agda version | `C-c C-x C-s` | | The binary is set in `g:nvim_agda_settings`. |
| Comment the rest of the buffer | `C-c C-x M-;` | | |
| Go to definition with the mouse | `mouse-2` | | `CTRL-]` works with the keyboard. |

Commands of the interface that the plugin never sends and Emacs does not
use interactively either: `Cmd_load_no_metas`, `Cmd_highlight`,
`Cmd_tokenHighlighting`, `Cmd_load_highlighting_info`, `Cmd_intro`
(refine uses it for empty goals), `ToggleImplicitArgs`.

## Arguments that are never used

* **Normalisation** (`Rewrite`: `AsIs`, `Instantiated`, `HeadNormal`,
  `Simplified`, `Normalised`) is fixed for every command: context
  `HeadNormal`, infer `Normalised`, helper function and auto `AsIs`,
  module contents and solve `Simplified`, goal type and context
  `Simplified` (`\u,` for `Normalised`).  The Emacs mode chooses with
  the prefix argument (none, `C-u`, `C-u C-u`).
* **Compute mode** (`ComputeMode`) is always `DefaultCompute`; Emacs
  offers `IgnoreAbstract` (`C-u`), `UseShowInstance` (`C-u C-u`) and
  `HeadCompute` (`C-u C-u C-u`).
* **Pattern-matching lambdas**: refine sends `Cmd_refine_or_intro
  False`, so refining an empty goal of function type introduces a plain
  lambda (`λ x → ?`), like the Emacs mode; Emacs introduces a
  pattern-matching lambda (`λ { x → ? }`) with a prefix argument.
* **Force** (`UseForce`) for give: **won't implement.**  It only skips
  two checks after the term is put into the goal (`give_` in
  `Interaction/BasicOps.hs`): re-running the termination check of the
  surrounding function, whose failure is only a warning and which the
  next load does anyway, and a double check of the term with the
  internal type checker, a safety net that should not fail for a term
  that was just checked.  It does not let one give ill-typed terms.
* **Ranges**: all goal commands send `noRange`, so Agda never uses the
  text of the goal as written (and `GiveAction` always has `str`, never
  `paren`).  The Emacs mode sends the goal's range when the input comes
  from the goal.
* **Load options**: `Cmd_load` gets only `--show-implicit` (when set).
* **Highlighting**: commands always ask for `Interactive` highlighting
  sent `Direct`ly, which is what an editor needs.

## Responses and information that are ignored

* `Status` (whether the file is checked, whether implicit and irrelevant
  arguments are shown): the Emacs mode shows it in the mode line.
* `Mimer`, `DoneAborting`, `DoneExiting`: not sent for the commands the
  plugin uses.
* `DisplayInfo` kinds for commands the plugin does not send:
  `CompilationOk`, `Time`, `SearchAbout`, `Version`, the goal-specific
  `CurrentGoal`, and the `GoalAndElaboration` part of a goal type.  If
  they arrive, the plugin says that it cannot show them.
* Highlighting:
  * `note`: a message for a range, e.g. the error at the range of an
    error ("Error.agda:7.7-9: error: [NotInScope] ...").  The Emacs mode
    shows it when the mouse is over the range; it could become a Neovim
    diagnostic or be shown for the range under the cursor.
  * `remove` and `tokenBased`, and `tokenBased` of `ClearHighlighting`:
    the plugin never removes highlighting for a range and clears all of
    it, whereas Agda distinguishes token-based highlighting.
* `RunningInfo`: the `debugLevel`.
* `Error`: the `warnings` that come with an error.
* Goal type and context: `outputForms` (constraints that mention the
  goal) and `rewrite`.
* Normal form and inferred type: `time`, `commandState`, `computeMode`.
* Why in scope: `filepath`.
* Constraints: `problems` and `unblocker` (what a constraint is blocked
  on).
* Context entries: everything is shown that the json has, but it has
  less than the Emacs mode shows (see doc/agda-upstream.md).

## Editor features

* While typing an input sequence such as `\alpha` there is no feedback:
  the input is done with insert-mode mappings, which show nothing until
  the sequence is complete.  A which-key-like display of the possible
  completions would help.
* When Agda's highlighting arrives after the file was edited, its
  offsets refer to the text that Agda loaded.  The plugin converts them
  with the loaded text, so the highlighting of edited parts is off until
  the next load; it could skip ranges in edited parts.
* Case splitting only handles clauses on the lines of the goal; see
  doc/make-case.md.
* Why in scope, infer and compute outside goals use the scope at the top
  level of the file; see doc/agda-upstream.md.
