-- Starting, stopping and losing the Agda process.
local t = require("harness")
local h = require("agda_helpers")

t.after_each = h.finish

t.test("a missing Agda binary is reported", function()
    h.open("missing_agda", { agda = "/nonexistent/agda" })
    vim.cmd("AgdaLoad")
    local errors = h.take_errors()
    t.eq(1, #errors, "errors: " .. vim.inspect(errors))
    t.ok(errors[1]:find("Cannot run `/nonexistent/agda --version`", 1, true), errors[1])
    -- On a modified buffer goal commands reload the file first and wait
    -- for the result; they must not be left waiting forever.
    for i = 1, 2 do
        vim.api.nvim_buf_set_lines(0, -1, -1, true, { "" })
        h.cursor_at("{! x !}", 1, 3)
        vim.cmd("AgdaTypeContext")
        t.eq(1, #h.take_errors(), "errors at attempt " .. i)
    end
    t.eq({}, h.messages)
end)

t.test("Agda versions are compared component-wise", function()
    -- The replayed Agda claims to be 3.0.0, which uses the same interface
    -- as the 2.8.0 that recorded the transcript.
    if h.skip_unless_replay() then return end
    h.open("auto_agda_3", { transcript = "auto", version = "3.0.0" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    h.cursor_at("?", 2)
    vim.cmd("AgdaAuto")
    h.wait_idle()
    t.golden("auto", h.lines())
end)
