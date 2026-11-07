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

t.test("Agda exiting is reported and the next command restarts it", function()
    if h.skip_when_recording() then return end
    h.open("restart", { transcript = "load" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    -- Simulate a crash.
    local job = h.agda_job()
    vim.fn.chanclose(job, "stdin")
    vim.fn.jobwait({ job }, 5000)
    vim.wait(20)
    t.eq({ "E: Agda exited unexpectedly (exit code 0)" }, h.take_errors())

    h.ctx.sessions = 2
    vim.cmd("AgdaLoad")
    h.wait_idle()
    t.golden("load_highlights", h.highlights())
end)

t.test("AgdaStop stops Agda silently", function()
    if h.skip_when_recording() then return end
    h.open("stop", { transcript = "load" })
    vim.cmd("AgdaLoad")
    h.wait_idle()
    local job = h.agda_job()
    vim.cmd("AgdaStop")
    t.eq({ job }, { vim.fn.jobwait({ job }, 5000)[1] ~= -1 and job }, "Agda exited")
    vim.wait(20)
    t.eq(nil, h.agda_job())
    t.eq({}, h.take_errors())
end)
