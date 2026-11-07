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
    vim.cmd("AgdaTypeContext")
    h.wait_idle()
    local fs = h.floats()
    t.eq(1, #fs, "number of floats")
    t.golden("type_context_wide", fs[1].lines)
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
