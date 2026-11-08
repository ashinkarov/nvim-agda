-- End-to-end tests of the interaction with Agda.  By default they run
-- against recorded transcripts; see tests/agda_helpers.lua.
local t = require("harness")
local h = require("agda_helpers")

t.after_each = h.finish

local function load(name)
    h.open(name)
    vim.cmd("AgdaLoad")
    h.wait_idle()
end

t.test("load highlights the file", function()
    load("load")
    t.golden("load_highlights", h.highlights())
end)

t.test("load reports goals", function()
    load("goals")
    h.messages = {}
    vim.cmd("PrintGoals")
    local out = table.concat(h.messages, "\n"):gsub(vim.pesc(h.ctx.dir), "$DIR")
    t.golden("goals", vim.split(out, "\n"))
end)

t.test("goal navigation", function()
    load("navigation")
    local visited = {}
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    for _ = 1, 4 do
        vim.cmd("GoalNext")
        table.insert(visited, h.cursor())
    end
    for _ = 1, 4 do
        vim.cmd("GoalPrev")
        table.insert(visited, h.cursor())
    end
    -- Cursor positions are {line, byte column}.  The goal on the last
    -- line follows wide characters (`pick 名前 y = ?`).
    t.eq({ { 7, 8 }, { 10, 17 }, { 13, 16 }, { 7, 8 },
           { 13, 16 }, { 10, 17 }, { 7, 8 }, { 13, 16 } }, visited)
end)

t.test("goal type and context", function()
    load("type_context")
    h.cursor_at("{! x !}", 1, 3)
    vim.cmd("AgdaTypeContext")
    h.wait_idle()
    local fs = h.floats()
    t.eq(1, #fs, "number of floats")
    t.golden("type_context", fs[1].lines)
end)

-- The outer x is shadowed: Agda prints it as x₁, and it is not in scope.
t.test("shadowed names in the context", function()
    h.open("context_shadowed", { fixture = "Shadow.agda" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    h.cursor_at("?", 1)
    vim.cmd("AgdaContext")
    h.wait_idle()
    local lines = h.floats()[1].lines
    t.eq({ "x₁ : 𝔹  (not in scope)", "x  : 𝔹" }, vim.list_slice(lines, #lines - 1))
    vim.cmd("AgdaCloseMsg")
    vim.cmd("AgdaTypeContext")
    h.wait_idle()
    lines = h.floats()[1].lines
    t.ok(vim.tbl_contains(lines, "x₁ : 𝔹  (not in scope)"), vim.inspect(lines))
end)

-- On a narrow screen the popup is as wide as the screen, its separators
-- as wide as the popup, and its height counts the wrapped lines.
t.test("popups fit narrow screens", function()
    h.open("type_context_narrow", { transcript = "type_context" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    local columns = vim.o.columns
    vim.o.columns = 12
    h.cursor_at("{! x !}", 1, 3)
    vim.cmd("AgdaTypeContext")
    h.wait_idle()
    local f = h.floats()[1]
    vim.o.columns = columns
    t.eq(12, f.width)
    local rows = 0
    for _, l in ipairs(f.lines) do
        if l:find("^─") then t.eq(string.rep("─", 12), l) end
        rows = rows + math.max(1, math.ceil(vim.api.nvim_strwidth(l) / 12))
    end
    t.eq(rows, vim.api.nvim_win_get_height(f.win))
    t.ok(rows > #f.lines, "no line wraps: " .. vim.inspect(f.lines))
end)

t.test("goal type and context after wide characters", function()
    load("type_context_wide")
    h.cursor_at("?", 2)        -- the goal in `pick`
    local goal = vim.fn.screenpos(0, 13, vim.fn.col("."))
    vim.cmd("AgdaTypeContext")
    h.wait_idle()
    local fs = h.floats()
    t.eq(1, #fs, "number of floats")
    t.golden("type_context_wide", fs[1].lines)
    -- The popup is below the goal, starting in its column.
    t.eq({ goal.row, goal.col - 1 }, vim.api.nvim_win_get_position(fs[1].win))
end)

t.test("infer type of a toplevel expression", function()
    load("infer_toplevel")
    h.stub_input("not")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("AgdaInfer")
    h.wait_idle()
    t.eq({ "Expression: " }, h.prompts)
    local fs = h.floats()
    t.eq(1, #fs, "number of floats; messages: " .. vim.inspect(h.messages))
    t.golden("infer_toplevel", fs[1].lines)
end)

t.test("give via the goal-edit window", function()
    load("give")
    h.cursor_at("?", 1)        -- the goal in `id′`, after λ and →
    local main = vim.api.nvim_get_current_win()
    vim.cmd("MkPrompt")
    t.ok(vim.api.nvim_get_current_win() ~= main, "prompt window is focused")
    vim.api.nvim_buf_set_lines(0, 0, -1, true, { "x" })
    vim.api.nvim_feedkeys(vim.keycode("<LocalLeader>r"), "x", false)
    h.wait_idle()
    t.eq("id′ = λ x → x", h.lines()[10])
    t.eq(0, #h.floats(), "prompt window closed")
end)

t.test("case split", function()
    load("make_case")
    h.cursor_at("{! x !}", 1, 3)
    vim.cmd("AgdaMakeCase")
    h.wait_idle()
    t.golden("make_case", h.lines())
end)

-- Splits the goal `goal` (the `n`th occurrence) in Case.agda and
-- returns the lines from `from` to `to` afterwards.
local function split_case(name, goal, n, from, to)
    h.open(name, { fixture = "Case.agda" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    h.cursor_at(goal, n, 3)
    vim.cmd("AgdaMakeCase")
    h.wait_idle()
    return vim.list_slice(h.lines(), from, to)
end

t.test("case split keeps the indentation of the clause", function()
    t.eq({ "  f : 𝔹 → 𝔹", "  f tt = ?", "  f ff = ?", "" },
         split_case("make_case_indent", "{! x !}", 1, 7, 10))
end)

t.test("case split in a λ where", function()
    t.eq({ "  k = λ where", "    tt → ?", "    ff → ?", "" },
         split_case("make_case_lambda_where", "{! x !}", 2, 11, 14))
end)

t.test("case split in the first clause of a λ", function()
    t.eq({ "l = λ { tt tt → ? ; tt ff → ? ; ff y → y }" },
         split_case("make_case_lambda_first", "{! y !}", 1, 15, 15))
end)

t.test("case split in a later clause of a λ", function()
    t.eq({ "m = λ { tt y → y ; ff tt → ? ; ff ff → ? }" },
         split_case("make_case_lambda_later", "{! y !}", 2, 18, 18))
end)

-- After a case split Agda sends the goals from before the split, so the
-- plugin reloads to learn the new ones.
t.test("goals are updated after a case split", function()
    load("make_case_goals")
    h.cursor_at("{! x !}", 1, 3)
    vim.cmd("AgdaMakeCase")
    h.wait_idle()
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("GoalNext")
    vim.cmd("GoalNext")
    t.eq({ 8, 9 }, vim.api.nvim_win_get_cursor(0))
end)

t.test("auto", function()
    load("auto")
    h.cursor_at("?", 2)        -- the goal in `pick`
    vim.cmd("AgdaAuto")
    h.wait_idle()
    t.golden("auto", h.lines())
end)

-- The transcript is load.json with the line "cannot read: garbage"
-- inserted into the middle of Agda's response.
t.test("non-json output is reported and does not stop the reader", function()
    if h.skip_unless_replay() then return end
    load("non_json_output")
    t.ok(vim.tbl_contains(h.messages, "E: Agda interaction error: cannot read: garbage"),
         "error reported: " .. vim.inspect(h.messages))
    h.messages = {}
    t.golden("load_highlights", h.highlights())
end)

-- Agda reads commands as Haskell, so the path has to be quoted as a
-- Haskell string.
t.test("file path with quotes and backslashes", function()
    h.open("unusual_path", { subdir = 'we"ird\\dir' })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    t.golden("load_highlights", h.highlights())
end)

-- Agda's own parser rejects control characters, but the command itself
-- has to get through (json escapes like \u001B made it "cannot read").
t.test("control characters in an expression reach Agda", function()
    load("control_characters")
    h.stub_input("not\27")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("AgdaInfer")
    h.wait_idle()
    t.eq({ "E: 1.1: error: [ParseError]\nLexical error (unprintable character):" },
         h.take_errors())
end)

t.test("module contents", function()
    h.open("module_contents", { fixture = "Modules.agda" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    h.stub_input("M")
    vim.cmd("AgdaModuleContents")
    h.wait_idle()
    t.eq({ "Module name (empty for the current module): " }, h.prompts)
    local fs = h.floats()
    t.eq(1, #fs, "number of floats; messages: " .. vim.inspect(h.messages))
    t.golden("module_contents", fs[1].lines)
end)

-- Shows the contents of the module `name` (asked for) and returns the
-- lines of the popup and the command sent.
local function module_contents(name)
    h.stub_input(name)
    vim.cmd("AgdaModuleContents")
    h.wait_idle()
    local cmds = h.sent_commands()
    return h.floats()[1].lines, cmds[#cmds]:match("%((Cmd.*)%)$")
end

t.test("module contents with submodules and of the current module", function()
    h.open("module_contents_submodules", { fixture = "Modules.agda" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    local lines = module_contents("Only")
    t.eq({ "Module Contents", "Modules", "  A", "  B", "Names" },
         vim.tbl_filter(function(l) return not l:find("^─") end, lines))
    lines = module_contents("")
    t.ok(vim.tbl_contains(lines, "  Only") and vim.tbl_contains(lines, "  top : M.T"),
         vim.inspect(lines))
end)

t.test("module contents in a goal", function()
    h.open("module_contents_goal", { fixture = "Modules.agda" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    h.cursor_at("{! M !}", 1, 3)
    local lines, cmd = module_contents("unused")
    t.eq('Cmd_show_module_contents Simplified 0 noRange "M"', cmd)
    t.eq({}, h.prompts)
    t.ok(vim.tbl_contains(lines, "  T : Set"), vim.inspect(lines))
end)

-- Tests of the edits that Agda's responses make to the buffer; see the
-- goals in tests/fixtures/Give.agda.
local function load_give(name)
    h.open(name, { fixture = "Give.agda" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
end

local function give(goal, n, text)
    h.cursor_at(goal, n)
    vim.cmd("MkPrompt")
    vim.api.nvim_buf_set_lines(0, 0, -1, true, { text })
    vim.api.nvim_feedkeys(vim.keycode("<LocalLeader>r"), "x", false)
    h.wait_idle()
end

t.test("give keeps the text after the goal", function()
    load_give("give_after")
    give("?", 1, "x")
    t.eq("after x = and x ff  -- comment", h.lines()[10])
end)

t.test("give indents the continuation lines of a long result", function()
    load_give("give_long")
    give("?", 2, "and (and (and (and x x) (and x x)) (and (and x x) (and x x)))"
              .. " (and (and (and x x) (and x x)) (and (and x x) (and x x)))")
    t.golden("give_long", h.lines())
end)

t.test("give edits the agda buffer when another window is current", function()
    load_give("give_other_window")
    local agda_buf = vim.api.nvim_get_current_buf()
    h.cursor_at("?", 1)
    vim.cmd("MkPrompt")
    vim.api.nvim_buf_set_lines(0, 0, -1, true, { "x" })
    -- Send the command, then move to another window before Agda replies.
    vim.fn.getbufvar(agda_buf, "AgdaMod").agda_refine(h.ctx.file, 0)
    vim.cmd("new")
    local other = vim.api.nvim_get_current_buf()
    h.wait_idle()
    t.eq("after x = and x ff  -- comment", h.lines()[10])
    t.eq({ "" }, vim.api.nvim_buf_get_lines(other, 0, -1, true))
end)

t.test("auto solves several goals on one line", function()
    load_give("auto_all")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("AgdaAuto")
    h.wait_idle()
    t.golden("auto_all", h.lines())
end)

t.test("solve fills several goals on one line", function()
    load_give("solve_all")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("AgdaSolve")
    h.wait_idle()
    t.eq("solved : Two (tt) (ff)", h.lines()[21])
end)

t.test("goal navigation after the first goal is filled", function()
    load_give("navigation_after_give")
    give("?", 1, "x")          -- goal 0, in `after`
    local visited = {}
    vim.api.nvim_win_set_cursor(0, { #h.lines(), 0 })
    for _ = 1, 2 do
        vim.cmd("GoalNext")
        table.insert(visited, h.cursor())
    end
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("GoalPrev")
    table.insert(visited, h.cursor())
    -- Wraps to the goals in `twice`, and from the top to the last goal in
    -- `solved`.
    t.eq({ { 13, 19 }, { 13, 29 }, { 21, 19 } }, visited)
end)

t.test("the goal-edit window is placed at the goal after wide characters", function()
    load("prompt_position")
    h.cursor_at("?", 2)        -- the goal in `pick`
    local goal = vim.fn.screenpos(0, 13, vim.fn.col("."))
    vim.cmd("MkPrompt")
    -- Below the goal, starting in its column.
    t.eq({ goal.row, goal.col - 1 },
         vim.api.nvim_win_get_position(vim.api.nvim_get_current_win()))
end)

t.test("the goal-edit window opens in a window created after loading", function()
    load("prompt_split")
    -- :split does not trigger BufWinEnter; close the original window.
    vim.cmd("split")
    vim.cmd("wincmd j | close")
    h.cursor_at("?", 1)
    vim.cmd("MkPrompt")
    t.eq(1, #h.floats(), "number of floats")
end)

t.test("loads and popups do not add autocommands", function()
    local function count()
        return #vim.api.nvim_get_autocmds({ event = { "BufWinEnter", "WinClosed", "BufUnload" } })
    end
    load("autocmds")
    h.cursor_at("{! x !}", 1, 3)
    vim.cmd("AgdaTypeContext")
    h.wait_idle()
    local before = count()
    vim.cmd("AgdaLoad")
    h.wait_idle()
    h.cursor_at("{! x !}", 1, 3)
    vim.cmd("AgdaTypeContext")
    h.wait_idle()
    t.eq(before, count())
end)

t.test("a failed reload with the goal-edit window open does not block goal commands", function()
    load_give("reload_error_with_prompt")
    h.cursor_at("?", 1)        -- goal 0, in `after`
    vim.cmd("MkPrompt")
    vim.api.nvim_buf_set_lines(0, 0, -1, true, { "x" })
    -- Break the file; the give has to reload it first, which fails.
    vim.api.nvim_buf_set_lines(h.ctx.buf, 6, 7, true, { "and a b = tt tt" })
    vim.api.nvim_feedkeys(vim.keycode("<LocalLeader>r"), "x", false)
    h.wait_idle()
    local errors = h.take_errors()
    t.eq(1, #errors, vim.inspect(errors))
    t.ok(errors[1]:find("CannotApply", 1, true), errors[1])
    -- Fix it and give again.
    vim.api.nvim_buf_set_lines(h.ctx.buf, 6, 7, true, { "and a b = a" })
    vim.api.nvim_feedkeys(vim.keycode("<LocalLeader>r"), "x", false)
    h.wait_idle()
    t.eq("after x = and x ff  -- comment", h.lines()[10])
end)

-- Without a clipboard provider (as in the tests) the normal form goes to
-- the unnamed register.
t.test("the normal form of a toplevel expression is copied", function()
    load_give("compute_toplevel")
    h.stub_input("and ff tt")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("AgdaCompute")
    h.wait_idle()
    t.eq("ff", vim.fn.getreg('"'))
    local fs = h.floats()
    t.eq(1, #fs, "number of floats")
    t.eq("Normal Form (copied to the \" register) : ff", fs[1].lines[2])
end)

t.test("the normal form in a goal is copied", function()
    load_give("compute_goal")
    h.cursor_at("?", 2)        -- the goal in `long`
    vim.cmd("MkPrompt")
    vim.api.nvim_buf_set_lines(0, 0, -1, true, { "and tt x" })
    vim.api.nvim_feedkeys(vim.keycode("<LocalLeader>n"), "x", false)
    h.wait_idle()
    t.eq("tt", vim.fn.getreg('"'))
    -- The goal-edit window stays open; the popup is the second float.
    local fs = h.floats()
    t.eq(2, #fs, "number of floats")
    t.eq("Normal Form (copied to the \" register) : tt", fs[2].lines[2])
end)

-- A buffer mapping that is a prefix of a global one (e.g. <LocalLeader>f
-- and \fg) waits 'timeoutlen' for more keys unless it is <nowait>.
-- feedkeys() does not wait, so we check the flags of the mappings.
t.test("the commands are defined for the Agda buffer only", function()
    load("buffer_commands")
    t.ok(vim.api.nvim_buf_get_commands(0, {}).AgdaLoad ~= nil, "AgdaLoad in the buffer")
    t.ok(vim.api.nvim_get_commands({}).AgdaLoad == nil, "AgdaLoad is global")
end)

-- The plugin does not change the standard groups, its own groups are
-- defaults that the user can override, and they survive :colorscheme.
t.test("highlight groups", function()
    vim.api.nvim_set_hl(0, "Todo", { bg = "#654321" })
    local todo = vim.api.nvim_get_hl(0, { name = "Todo" })
    vim.api.nvim_set_hl(0, "NoDefinition", { bg = "#123456" })
    load("highlight_groups")
    t.eq(todo, vim.api.nvim_get_hl(0, { name = "Todo" }))
    t.eq(0x123456, vim.api.nvim_get_hl(0, { name = "NoDefinition" }).bg)
    vim.api.nvim_set_hl(0, "NoDefinition", {})
    vim.cmd("colorscheme default")
    t.eq(0x353535, vim.api.nvim_get_hl(0, { name = "AgdaHole" }).bg)
    t.eq(0x354657, vim.api.nvim_get_hl(0, { name = "NoDefinition" }).bg)
    t.eq("AgdaHole", vim.api.nvim_get_hl(0, { name = "AgdaUnsolvedMeta" }).link)
    t.eq("DiagnosticUnderlineWarn", vim.api.nvim_get_hl(0, { name = "AgdaCoverageProblem" }).link)
end)

-- The error is at `名前` (line 7, column 7 in code points).
t.test("a failed load jumps to the error", function()
    h.open("jump_to_error", { fixture = "Error.agda" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    t.eq(1, #h.take_errors())
    t.eq({ 7, 6 }, vim.api.nvim_win_get_cursor(0))
end)

t.test("an error in an imported module does not move the cursor", function()
    h.open("jump_to_error_import", { fixture = "Error.agda" })
    vim.fn.writefile({ "module Main where", "open import Error" }, h.ctx.dir .. "/Main.agda")
    local error_buf = h.ctx.buf
    vim.cmd("edit " .. h.ctx.dir .. "/Main.agda")
    vim.cmd("bwipeout " .. error_buf)
    h.ctx.buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_win_set_cursor(0, { 2, 3 })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    t.eq(1, #h.take_errors())
    t.eq({ 2, 3 }, vim.api.nvim_win_get_cursor(0))
end)

t.test("superscript digits and signs", function()
    h.open("superscripts")
    vim.api.nvim_feedkeys("Gox\\^2\\^-\\^(\27", "xt", false)
    t.eq("x²⁻⁽", h.lines()[#h.lines()])
end)

t.test("comments", function()
    h.open("comments")
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.cmd("normal gcc")
    t.eq("-- module Basic where", h.lines()[1])
end)

local function load_constraints(name)
    h.open(name, { fixture = "Constraints.agda" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
end

t.test("goals are listed like Agda prints them", function()
    load_constraints("constraint_goals")
    local goals = h.messages[#h.messages]
    t.ok(goals:find("Visible Goals\n    ?0 : 𝔹\n    ?1 : P tt\n", 1, true), goals)
    t.ok(goals:find("Invisible Goals\n    _5 : 𝔹  [at 8.9-10]", 1, true), goals)
end)

t.test("show constraints", function()
    load_constraints("show_constraints")
    h.messages = {}
    vim.cmd("AgdaShowConstraints")
    h.wait_idle()
    t.eq({ "Constraints\n    G _x_13 = tt : 𝔹\n    _14 := q" }, h.messages)
end)

t.test("refine on an empty goal", function()
    load_constraints("refine_intro")
    h.messages = {}
    h.cursor_at("?", 1)        -- s : 𝔹
    vim.cmd("AgdaRefine")
    h.wait_idle()
    h.cursor_at("?", 2)        -- t : P tt
    vim.cmd("AgdaRefine")
    h.wait_idle()
    t.eq({ "Don't know which constructor to introduce of tt or ff",
           "No introduction forms found." }, h.messages)
end)

t.test("highlighting of records, fields and problems", function()
    h.open("highlight_problems", { fixture = "Problems.agda" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    t.golden("highlight_problems", h.highlights())
end)

-- Definitions.agda imports Lib, which the tests write next to it.
local function load_definitions(name)
    h.open(name, { fixture = "Definitions.agda" })
    vim.fn.writefile({ "module Lib where", "", "data Unit : Set where", "  unit : Unit" },
                     h.ctx.dir .. "/Lib.agda")
    vim.cmd("AgdaLoad")
    h.wait_idle()
end

local function jump()
    vim.cmd("normal! \29")    -- CTRL-]
    return vim.api.nvim_win_get_cursor(0)
end

t.test("CTRL-] jumps to the definition and CTRL-T back", function()
    load_definitions("definition_same_file")
    h.cursor_at("x ∧ tt", 1, 2)    -- on ∧
    t.eq({ 8, 0 }, jump())         -- _∧_
    vim.cmd("normal! \20")    -- CTRL-T
    t.eq({ 13, 8 }, vim.api.nvim_win_get_cursor(0))
    h.cursor_at("∧ tt", 1, 4)      -- on tt
    t.eq({ 6, 2 }, jump())
end)

t.test("CTRL-] finds definitions after edits", function()
    load_definitions("definition_after_edit")
    vim.api.nvim_buf_set_lines(0, 1, 1, true, { "-- added", "-- lines" })
    h.cursor_at("x ∧ tt", 1, 2)
    t.eq({ 10, 0 }, jump())
end)

t.test("CTRL-] jumps to definitions in other files", function()
    load_definitions("definition_other_file")
    h.cursor_at("u = unit", 1, 4)
    t.eq({ 4, 2 }, jump())
    t.eq(h.ctx.dir .. "/Lib.agda", vim.api.nvim_buf_get_name(0))
    local lib = vim.api.nvim_get_current_buf()
    vim.cmd("normal! \20")
    t.eq(h.ctx.buf, vim.api.nvim_get_current_buf())
    vim.cmd("bwipeout " .. lib)
end)

t.test("CTRL-] outside names leaves the cursor alone", function()
    load_definitions("definition_none")
    h.cursor_at("like", 1)
    local before = vim.api.nvim_win_get_cursor(0)
    pcall(vim.cmd, "normal! \29")
    t.eq(before, vim.api.nvim_win_get_cursor(0))
end)

-- Asks why-in-scope with the cursor at the `n`th `s` (moved by `off`
-- bytes) and returns the command sent to Agda.
local function why_in_scope(s, n, off)
    h.cursor_at(s, n, off)
    vim.cmd("AgdaWhyInscope")
    h.wait_idle()
    local cmds = h.sent_commands()
    return cmds[#cmds]:match("%((Cmd_why_in_scope.*)%)$")
end

t.test("why in scope asks about the name under the cursor", function()
    load_definitions("why_in_scope")
    -- An infix and a mixfix operator part, a qualified operator.
    t.eq('Cmd_why_in_scope_toplevel "_∧_"', why_in_scope("x ∧ tt", 1, 2))
    t.eq('Cmd_why_in_scope_toplevel "if_then_else_"', why_in_scope("then ff", 1, 0))
    t.eq('Cmd_why_in_scope_toplevel "M.if_then_else_"', why_in_scope("M.if_", 1, 3))
    t.eq('Cmd_why_in_scope_toplevel "unit"', why_in_scope("u = unit", 1, 4))
    t.ok(vim.tbl_contains(h.floats()[1].lines, "Why `unit' is in scope at the top level"),
         vim.inspect(h.floats()[1].lines))
end)

t.test("why in scope in a goal uses the goal", function()
    load_definitions("why_in_scope_goal")
    t.eq('Cmd_why_in_scope 0 noRange "x"', why_in_scope("{! x !}", 1, 3))
    t.ok(vim.tbl_contains(h.floats()[1].lines, "Why `x' is in scope in goal ?0"),
         vim.inspect(h.floats()[1].lines))
end)

t.test("why in scope outside names asks with a guess", function()
    load_definitions("why_in_scope_prompt")
    h.stub_input("tt")
    t.eq('Cmd_why_in_scope_toplevel "tt"', why_in_scope("Lib.unit)", 1, 5))
    t.eq({ "Name: " }, h.prompts)
    t.eq({ "Lib.unit" }, h.input_texts)
end)

t.test("a file changed on disk is reloaded before loading it", function()
    h.open("changed_on_disk")
    vim.o.autoread = true
    local lines = vim.fn.readfile(h.ctx.file)
    table.insert(lines, 1, "-- changed on disk")
    vim.fn.writefile(lines, h.ctx.file)
    local future = os.time() + 10
    vim.uv.fs_utime(h.ctx.file, future, future)
    vim.cmd("AgdaLoad")
    h.wait_idle()
    vim.o.autoread = false
    t.eq("-- changed on disk", h.lines()[1])
    t.ok(vim.tbl_contains(h.highlights(), "1:0-6 Keyword module"), vim.inspect(h.highlights()))
end)

t.test("unsolved metas have their own highlight group", function()
    h.open("unsolved_meta", { fixture = "Meta.agda" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    t.ok(vim.tbl_contains(h.highlights(), "7:8-9 AgdaUnsolvedMeta _"), vim.inspect(h.highlights()))
end)

t.test("the mappings do not wait for longer global mappings", function()
    load("mapping_nowait")
    local maps = vim.api.nvim_buf_get_keymap(0, "n")
    t.ok(#maps >= 18, "number of mappings: " .. #maps)
    for _, m in ipairs(maps) do
        t.ok(m.nowait == 1 and m.noremap == 1, "mapping " .. m.lhs)
    end
end)
