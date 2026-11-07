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
    t.eq({ "Module Name: " }, h.prompts)
    local fs = h.floats()
    t.eq(1, #fs, "number of floats; messages: " .. vim.inspect(h.messages))
    t.golden("module_contents", fs[1].lines)
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
