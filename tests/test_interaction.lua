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
    -- Cursor positions are {line, byte column}.
    -- FIXME: the cursor column is computed with virtcol, so on the line
    -- `pick 名前 y = ?` the cursor appears to be after the goal and
    -- GoalPrev gets stuck there.  Should be:
    --   { 13, 16 }, { 10, 17 }, { 7, 8 }, { 13, 16 }
    t.eq({ { 7, 8 }, { 10, 17 }, { 13, 16 }, { 7, 8 },
           { 13, 16 }, { 13, 16 }, { 13, 16 }, { 13, 16 } }, visited)
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
    -- FIXME: same virtcol problem as in "goal navigation".
    t.eq(0, #h.floats(), "number of floats")
    t.eq({ "Warning: cannot obtain goal type and context, the cursor is not in the goal" },
         vim.list_slice(h.messages, #h.messages))
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
    -- FIXME: because of the virtcol problem (see "goal navigation") the
    -- cursor is not recognised as being in the goal, so this solves all
    -- goals instead of only the one in `pick`.
    vim.cmd("AgdaAuto")
    h.wait_idle()
    t.golden("auto", h.lines())
end)
