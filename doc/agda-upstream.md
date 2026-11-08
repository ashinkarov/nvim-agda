# Things to improve in Agda's interaction interface

Places where Agda's `--interaction-json` interface is inconsistent,
undocumented or loses information, found while working on this plugin.
For each: what happens, what the plugin does about it, and what could
change in Agda.  Source references are to Agda 2.8.0
(`src/full/Agda/...`).

## 1. Toplevel commands only know the scope at the top level

`Cmd_why_in_scope_toplevel`, `Cmd_infer_toplevel` and
`Cmd_compute_toplevel` run in `atTopLevel` (`Interaction/BasicOps.hs`),
which uses `iInsideScope` of the top-level module: the scope at the end
of the file, outside nested modules.  Names that a nested module opens
or imports are private to it, so in

    postulate bar : Set

    module Test where
      open import Data.Nat
      foo : ℕ → ℕ
      foo x = x + x

asking why `_+_` is in scope from inside `Test` answers "_+_ is not in
scope", and so would inferring `x + 1` there.  The Emacs mode has the
same problem.  The only other scope a command can use is that of a goal.

*Plugin:* the header of the answer says "at the top level" or "in goal
?n", and the README suggests putting a `?` where one wants to ask.

*Proposal:* let these commands take a position (or a range, like the
goal commands), and answer in the scope of the innermost module that
contains it.  Agda keeps the scope of every module (`scopeModules` in
the scope info), with its private name space, where `open` puts the
names it brings in, so this should not need new bookkeeping for modules
(to check in a prototype).  (Scopes inside definitions,
such as `where` blocks and `let`, would need more.)

## 2. Case splitting does not say which text to replace

See [make-case.md](make-case.md): Agda sends the new clauses without the
range of the clause they replace, so every editor guesses.

## 3. The framing of the json output is not documented

Every response is one line, because `jsonREPL` writes each message with
`BS.putStrLn` of aeson's compact encoding (`Interaction/JSONTop.hs`).
Clients rely on this, but it is a property of the implementation rather
than of the format (json allows newlines between tokens).

Before reading each command, the REPL prints the prompt `JSON> ` without
a newline (`interact'` in `Interaction/AgdaTop.hs`), so it ends up in
front of the first message of the next response.  In json mode the
prompt serves no purpose and every client strips it.

*Plugin:* reads the output line by line and strips the prompt (see the
comment above `handle_line` in `lua/agda/init.lua`).

*Proposal:* document one message per line, and print no prompt in json
mode (or print it on a line of its own).

## 4. Command errors are plain text

If a command cannot be parsed, Agda prints `cannot read: ...` or `not
consumed: ...` (`parseIOTCM` in `Interaction/Base.hs`) with `putStrLn`,
not as json, on stdout.

*Plugin:* reports lines that are not json as errors.

*Proposal:* send these as a json response, e.g. a `DisplayInfo` error.

## 5. Commands are Haskell, responses are json

Commands are parsed with Haskell's `reads` (`parseIOTCM`), so strings in
commands have to be Haskell string literals (`"\27\&"`), while the
responses are json.  A client that quotes strings as json, which is the
natural thing to do in a json interface, gets `cannot read` as soon as a
string contains a control character (`\u001B` is not Haskell).

*Plugin:* quotes strings as Haskell literals (`lua/agda/haskell.lua`).

*Proposal:* accept commands as json in json mode, or at least document
the format and the quoting.

## 6. The meaning of highlighting updates is not documented

During a load Agda sends the same ranges several times (token-based
highlighting, then again after type checking), sends `typechecks` for
whole definitions while checking them, and sends updates with no atoms
at all.  The atoms list the other aspects (errors, problems,
`typechecks`) before the kind of name (`toAtoms` in
`Interaction/Highlighting/Common.hs`), and ranges that are not names
come with `"definitionSite": null`.  It is not documented whether an
update for a range replaces or adds to the earlier ones, or what an
update without atoms means.

*Plugin:* replaces the highlighting of exactly the same range, keeps it
for updates without known atoms, and layers all atoms of a range
(`handle_hl`).  Replacing everything inside a range is wrong, as
`typechecks` updates cover whole definitions.

*Proposal:* document the semantics of updates (and of `typechecks`), or
make removals explicit.

## 7. Constraints are sent as structures

Goals and constraints (`AllGoalsWarnings`, `Constraints`) are encoded
as structures with about 20 kinds (`encodeOC` in
`Interaction/JSONTop.hs`), so every client re-implements Agda's pretty
printer (the `Pretty OutputConstraint` instance in
`Interaction/BasicOps.hs`).  Some information is missing: instance
candidates have no names (`-- TODO: encode kind` in `encodeOC`), and the
meta a constraint is blocked on comes as a number, so a client cannot
print "(blocked on _x_13)" as Agda's own messages do.

*Plugin:* prints them like Agda (`lua/agda/constraint.lua`), without the
missing parts.

*Proposal:* add the pretty-printed text to every constraint, next to the
structure.

## 8. Context entries lack what the Emacs mode shows

The Emacs mode shows `x = x₁` when the original name of a variable is
still in scope, and marks variables as erased, irrelevant or instances,
and shows the values of let-bound variables (`prettyResponseContext` in
`Interaction/EmacsTop.hs`).  The json entries have `originalName`,
`reifiedName`, `binding` and `inScope` (of the reified name) only
(`EncodeTCM ResponseContextEntry` in `Interaction/JSONTop.hs`).

*Plugin:* shows the reified names and marks those not in scope.

*Proposal:* add whether the original name is in scope, the modality and
the let value.

## 9. Interaction points after a case split are stale

After `MakeCase`, Agda sends `InteractionPoints`
(`updateInteractionPointsAfter Cmd_make_case = True` in
`Interaction/InteractionTop.hs`) with the ranges from before the split,
which are wrong as soon as the editor has inserted the clauses.

*Plugin:* reloads after a case split, like the Emacs mode.

*Proposal:* do not send them after a case split, or say in the
documentation that the file has to be reloaded.

## 10. Everything goes to stdout

Agda writes all its output to stdout: the json responses, the errors in
them, the plain-text command errors (item 4) and the prompt.  Writing
errors (or at least the non-json ones) to stderr would let a client
tell them apart without parsing, but it would change what existing
clients see, so it is a nice-to-have that needs a breaking change (or a
new option).

*Plugin:* reads stdout only for responses; non-json lines are reported
as errors, and stderr output is reported as well.
