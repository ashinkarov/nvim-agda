local t = require("harness")
local h = require("agda_helpers")
local msg = require("agda.msg")

t.test("message layout", function()
    t.eq({ { "Checking Basic." }, nil }, { msg.layout("Checking Basic.\n", 20) })
    t.eq({ { "a", "", "b" }, { "a", "  [+2 lines, see :messages]" } },
         { msg.layout("\na  \n\nb\n", 40) })
    -- Long lines are split at the width, counted in display cells.
    t.eq({ { "名前名前", "名前x" }, { "名前名前", "" } },
         { msg.layout("名前名前名前x", 8) })
    -- A character wider than the width still makes progress.
    t.eq({ { "名", "前" }, { "名", "" } }, { msg.layout("名前", 1) })
    -- The summary is shortened to fit.
    local _, summary = msg.layout(string.rep("x", 30) .. "\ny", 40)
    t.eq({ string.rep("x", 12) .. "…", "  [+1 lines, see :messages]" }, summary)
end)

-- Runs Neovim with a UI in a terminal and checks that messages shown
-- while a command runs and from a callback do not ask to press ENTER.
t.test("messages do not ask to press ENTER", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local sock = dir .. "/nvim.sock"
    vim.cmd("enew")
    local term = vim.api.nvim_get_current_buf()
    local job = vim.fn.jobstart({ vim.env.AGDA_TEST_NVIM or "nvim", "--clean", "--listen", sock },
                                { term = true, width = 60, height = 10 })
    t.ok(vim.wait(5000, function() return vim.uv.fs_stat(sock) ~= nil end), "nvim started")
    local ch = vim.fn.sockconnect("pipe", sock, { rpc = true })
    -- Messages given during startup always ask to press ENTER.
    t.ok(vim.wait(5000, function() return vim.rpcrequest(ch, "nvim_get_vvar", "vim_did_enter") == 1 end),
         "nvim finished starting")
    vim.wait(200)
    local function blocked()
        vim.wait(300)
        return vim.rpcrequest(ch, "nvim_get_mode").blocking
    end
    local ok, err = pcall(function()
        local long = string.rep("long ", 12)
        vim.rpcrequest(ch, "nvim_exec_lua", [[
            local root, long = ...
            vim.opt.rtp:prepend(root)
            local show = require("agda.msg").show
            vim.api.nvim_create_user_command("T", function()
                show("Checking Basic.\n")
                show("Visible Goals\n  0 : 𝔹\n  1 : 𝔹")
                show(long)
            end, {})
            vim.defer_fn(function()
                show("error\nwhen checking", "ErrorMsg")
                show(long)
            end, 10)
        ]], { t.root, long })
        t.ok(not blocked(), "callback asks to press ENTER")
        vim.rpcrequest(ch, "nvim_input", ":T<CR>")
        t.ok(not blocked(), "command asks to press ENTER")
        -- All lines are in the history, split as wide as messages can be.
        local width = vim.rpcrequest(ch, "nvim_get_vvar", "echospace")
        local expected = {}
        for _, m in ipairs({ "error\nwhen checking", long, "Checking Basic.\n",
                             "Visible Goals\n  0 : 𝔹\n  1 : 𝔹", long }) do
            vim.list_extend(expected, (msg.layout(m, width)))
        end
        local hist = vim.rpcrequest(ch, "nvim_exec2", "messages", { output = true }).output
        t.eq(table.concat(expected, "\n"), hist)
        -- The screen shows the summary of the last message.
        local _, summary = msg.layout(long, width)
        local screen = vim.api.nvim_buf_get_lines(term, 0, -1, false)
        local last = table.concat(summary)
        t.eq(last, screen[#screen]:sub(1, #last))
    end)
    vim.fn.jobstop(job)
    vim.cmd("bwipeout!")
    if not ok then error(err, 0) end
end)
