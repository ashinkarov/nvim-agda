# Case splitting: what is wrong and how to fix it in Agda

Status: open.  The plugin currently uses the workaround described below;
the proper fix needs a change in Agda.

## The problem

For `Cmd_make_case`, Agda answers with

    {"kind": "MakeCase", "variant": "Function" | "ExtendedLambda",
     "interactionPoint": {"id": ..., "range": [...]},
     "clauses": ["f tt = ?", "f ff = ?"]}

The clauses are printed on one line each (`decorate` uses `OneLineMode`
in `Agda/Interaction/InteractionTop.hs`), without indentation, from the
abstract syntax, so formatting and comments of the original clause are
lost.  `where` blocks are dropped (`makeAbstractClause` in
`Agda/Interaction/MakeCase.hs` uses `A.noWhereDecls`).  For extended
lambdas the function name is dropped and the last ` = ` is replaced by
an arrow (`extlam_dropName`, "very dirty hack").

Crucially, the response does not say which text the clauses replace:
only the range of the goal is known.  Every client guesses:

* The Emacs mode (`agda2-make-case-action` in `agda2-mode.el`) replaces
  the line of the point from its indentation to its end, and indents
  further clauses to the same column.  For extended lambdas
  (`agda2-make-case-action-extendlam`) it searches backwards from the
  goal for `;` or an unmatched `{` and replaces from there to the end of
  the goal, or, if there is neither, treats it as a `λ where`.
* This plugin (`handle_make_case` in `lua/agda/init.lua`) does the same,
  based on the goal's range rather than the cursor: it replaces the
  lines of the goal by the clauses indented like the first line, or the
  extended lambda clause like Emacs does.

The guess is wrong whenever the clause is not on the lines of the goal:

    g x                  -- left-hand side on several lines (#1146, #5009)
      y = {! y !}

    f x = boo x          -- the goal on a later line of the right-hand side
          {! x !}

    h x = id {! x !} where id : 𝔹 → 𝔹   -- the `where` block is deleted
                           id z = z      -- and this line is left dangling

    f (c
         x
      ) = {! x !}        -- the patterns span several lines (#5009)

Text after the goal that belongs to the clause is duplicated or lost,
and goals that span several lines make it worse.

## Upstream issues

* agda/agda#1146 "Case splitting doesn't work with multiple lines
  definitions" (open, 2014).
* agda/agda#2628 "case splitting only works when hole is the last thing
  on the line" (open, 2017).  Andreas Abel: Emacs cannot do better as
  the buffer may have changed since the last load; Agda would have to
  tell the editor the clause boundaries.  Jesper Cockx and Andreas then
  agree that when the buffer is unchanged since the load, the editor can
  replace the whole clause, if Agda says which part to replace.
* agda/agda#5009 "Case splitting patterns that span across multiple
  lines" (ours, closed as a duplicate of the two above).
* agda/agda#575 "Indenting lost on case-split" (open).
* agda/agda#2800 "Case split with non-trivial RHS should either be
  disallowed or do the right thing" (open): the right-hand side may
  mention the variable that was split.  gallais suggests `x@zero` and
  `x@(suc x')` patterns.
* ashinkarov/nvim-agda#8 indents the clauses like the goal's line, which
  the plugin now does.

## Why the range would be exact for this plugin

Andreas's objection is that the buffer may differ from what Agda loaded.
The plugin reloads before every goal command if the buffer was modified
(`wrap_goal_action`), so when Agda answers a case split, the buffer is
exactly what Agda checked, and any range Agda sends is valid.  (The
Emacs mode could use the range when the buffer is unmodified since the
last load.)

## Proposed change in Agda

1. Add the range of the clause that is split to the response:

       {"kind": "MakeCase", ..., "clauseRange": [...]}

   Agda has it: the interaction point stores the clause as written
   (`ipcClause :: A.SpineClause` in `IPClause`,
   `Agda/TypeChecking/Monad/Base.hs`), and `Cmd_make_case` in
   `InteractionTop.hs` looks it up in `makeCase`.  The range should
   cover the left-hand side and the right-hand side, but not the `where`
   block, since Agda does not print it; `getRange` of an `A.Clause`
   includes the `where` declarations, so take `getRange (lhs, rhs)`.
   Adding a field keeps existing JSON clients working; the Emacs
   response (`lispifyResponse` in `EmacsTop.hs`) could get the range as
   an extra optional argument.

   To check in a prototype:
   * the abstract ranges are those of the concrete syntax as written,
     including a left-hand side and right-hand side on several lines;
   * the range for an absurd clause (`AbsurdRHS` has no range) and for
     `with` clauses;
   * for an extended lambda, `ipcClause` is the clause of the lambda,
     not of the enclosing function.

2. Optionally, in the same spirit:
   * keep the `where` block (print it after the last clause, or not
     cover it by the range, as above, so that it stays in place);
   * print the right-hand side with `@`-patterns as in #2800, so that
     references to the split variable stay correct.

## Changes in the plugin once Agda sends the range

* If `clauseRange` is present, replace exactly that range with the
  clauses, the first one at the start of the range, the others on new
  lines indented to the column of the start of the range.  For extended
  lambdas, separate the clauses with ` ; ` unless the clause is the
  first thing on its line (a `λ where`).
* Otherwise, keep the current workaround.
* Test against the examples above (tests/fixtures/Case.agda has the
  simple cases).
