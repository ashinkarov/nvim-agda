-- Helpers for tests that drive the plugin against an Agda process.
--
-- The `agda` binary is replaced by tests/bin/agda, which depending on
-- AGDA_TEST_MODE either replays a recorded transcript (the default) or
-- runs the real Agda:
--
--   AGDA_TEST_MODE=replay  replay tests/transcripts/<test>.json
--   AGDA_TEST_MODE=live    run the real Agda
--   AGDA_TEST_MODE=record  run the real Agda and (re)write the transcripts
--
-- A transcript is a JSON object {"agda": <version>, "exchanges": [...]}
-- where every exchange is a pair [command, raw stdout].  The first
-- exchange has an empty command and holds the output Agda prints before
-- reading its first command.  Every output chunk ends with Agda's
-- "JSON> " prompt.  The test directory is replaced by "$DIR".

local t = require("harness")

local M = {}

local PROMPT = "JSON> "
local mode = vim.env.AGDA_TEST_MODE or "replay"
local seed = tonumber(vim.env.AGDA_TEST_SEED) or os.time()
local timeout = (mode == "replay") and 10000 or 60000

M.mode = mode
io.stdout:write(string.format("agda mode: %s, seed: %d\n", mode, seed))

-- Capture messages instead of printing them to the terminal.
M.messages = {}
_G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring((select(i, ...)))
    end
    table.insert(M.messages, table.concat(parts, "\t"))
end
vim.api.nvim_err_writeln = function(msg)
    table.insert(M.messages, "E: " .. msg)
end

local real_input = vim.fn.input

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
end

-- Positions (1-based) at which Agda printed a prompt.
local function prompts(s)
    local r = {}
    local init = 1
    while true do
        local p = s:find(PROMPT, init, true)
        if not p then break end
        if p == 1 or s:sub(p - 1, p - 1) == "\n" then
            table.insert(r, p)
        end
        init = p + 1
    end
    return r
end

local function commands(s)
    local r = {}
    for _, l in ipairs(vim.split(s or "", "\n")) do
        if l ~= "" then table.insert(r, l) end
    end
    return r
end

local function transcript_path(name)
    return t.root .. "/tests/transcripts/" .. name:gsub("[^%w]+", "_") .. ".json"
end

-- Open a copy of tests/fixtures/<fixture> in a fresh temporary directory.
-- `name` identifies the transcript of this test.
function M.open(name, fixture)
    fixture = fixture or "Basic.agda"
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/" .. fixture
    vim.fn.writefile(vim.fn.readfile(t.root .. "/tests/fixtures/" .. fixture, "b"), file, "b")

    vim.env.AGDA_TEST_MODE = mode
    vim.env.AGDA_TEST_DIR = dir
    vim.env.AGDA_TEST_SEED = tostring(seed)
    vim.env.AGDA_TRANSCRIPT = transcript_path(name)
    vim.g.nvim_agda_settings = { agda = t.root .. "/tests/bin/agda" }
    vim.v.errmsg = ""

    vim.cmd.edit(vim.fn.fnameescape(file))
    M.ctx = { name = name, dir = dir, file = file, buf = vim.api.nvim_get_current_buf() }
    return M.ctx
end

local function check_replay_error()
    local err = read(M.ctx.dir .. "/replay-error")
    if err then
        error("replay failed: " .. err, 0)
    end
end

-- Agda is idle when it has printed one prompt more than the number of
-- commands it has received.
local function state()
    local n = #commands(read(M.ctx.dir .. "/stdin.log"))
    local p = #prompts(read(M.ctx.dir .. "/stdout.log") or "")
    return n, p
end

-- Wait until Agda has answered all commands, including the ones the
-- plugin sends in response to Agda's output.
function M.wait_idle()
    while true do
        local ok = vim.wait(timeout, function()
            if mode == "replay" then check_replay_error() end
            local n, p = state()
            return p >= n + 1
        end, 10)
        if not ok then
            local n, p = state()
            error(string.format("timeout waiting for Agda (%d commands, %d prompts)", n, p), 2)
        end
        local n0, p0 = state()
        -- Give the plugin time to process the output (and possibly send
        -- more commands).
        vim.wait(100)
        local n1, p1 = state()
        if n0 == n1 and p0 == p1 then
            return
        end
    end
end

-- Make vim.fn.input return `answer` (and record the prompt).
function M.stub_input(answer)
    M.prompts = {}
    vim.fn.input = function(prompt)
        table.insert(M.prompts, prompt)
        return answer
    end
end

local function save_transcript()
    local ctx = M.ctx
    local inp = read(ctx.dir .. "/stdin.log")
    local out = read(ctx.dir .. "/stdout.log")
    if not out then return end
    local cmds = commands(inp)
    local ps = prompts(out)
    if #ps ~= #cmds + 1 then
        error(string.format("incomplete recording: %d commands, %d prompts", #cmds, #ps))
    end
    local function norm(s)
        return (s:gsub(vim.pesc(ctx.dir), "$DIR"))
    end
    local ex = {}
    local start = 1
    for i, p in ipairs(ps) do
        local stop = p + #PROMPT - 1
        local cmd = (i == 1) and "" or norm(cmds[i - 1])
        table.insert(ex, vim.json.encode({ cmd, norm(out:sub(start, stop)) }))
        start = stop + 1
    end
    local version = vim.trim(vim.fn.system({ vim.env.AGDA_REAL or "agda", "--version" }))
        :match("^[^\n]*")
    local path = transcript_path(ctx.name)
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local f = assert(io.open(path, "wb"))
    f:write('{"agda":', vim.json.encode(version), ',"exchanges":[\n',
            table.concat(ex, ",\n"), "\n]}\n")
    f:close()
end

local function check_transcript_consumed()
    local ctx = M.ctx
    local data = vim.json.decode(read(transcript_path(ctx.name)))
    local n = #commands(read(ctx.dir .. "/stdin.log"))
    t.eq(#data.exchanges - 1, n, "commands replayed")
end

-- Run after each test: verify/save the transcript and reset the editor.
function M.finish()
    local ctx = M.ctx
    M.ctx = nil
    vim.fn.input = real_input

    local jobs = {}
    for _, ch in ipairs(vim.api.nvim_list_chans()) do
        if ch.stream == "job" then
            -- Closing stdin is enough for both Agda and the replay
            -- script, which blocks reading stdin and so cannot handle
            -- the SIGTERM sent by jobstop() promptly.
            vim.fn.chanclose(ch.id, "stdin")
            vim.fn.jobstop(ch.id)
            table.insert(jobs, ch.id)
        end
    end
    -- Let the exit callbacks run before resetting the messages.
    vim.fn.jobwait(jobs, 2000)
    vim.wait(20)
    M.messages = {}
    for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_config(w).relative ~= "" then
            pcall(vim.api.nvim_win_close, w, true)
        end
    end
    vim.cmd("silent! %bwipeout!")

    if not ctx then return end
    M.ctx = ctx
    local errmsg = vim.v.errmsg
    if mode == "replay" then
        check_replay_error()
        check_transcript_consumed()
    elseif mode == "record" then
        save_transcript()
    end
    M.ctx = nil
    if errmsg ~= "" then
        error("unexpected error message: " .. errmsg, 0)
    end
end

------ Inspecting the editor ------

-- Put the cursor on the `n`-th (default first) occurrence of the plain
-- string `s`, optionally moved by `off` bytes.
function M.cursor_at(s, n, off)
    n = n or 1
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, true)
    for row, l in ipairs(lines) do
        local init = 1
        while true do
            local c = l:find(s, init, true)
            if not c then break end
            n = n - 1
            if n == 0 then
                vim.api.nvim_win_set_cursor(0, { row, c - 1 + (off or 0) })
                return
            end
            init = c + 1
        end
    end
    error("cannot find " .. vim.inspect(s), 2)
end

function M.cursor()
    return vim.api.nvim_win_get_cursor(0)
end

function M.lines(buf)
    return vim.api.nvim_buf_get_lines(buf or M.ctx.buf, 0, -1, true)
end

-- Highlights in the plugin's namespace, one line per highlighted
-- segment: "row:startcol-endcol Group text", where columns are bytes and
-- multi-line marks are split per line.
function M.highlights(buf)
    buf = buf or M.ctx.buf
    local ns = vim.api.nvim_get_namespaces()["agda-hl-ns"]
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, true)
    local segs = {}
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        local row, col, d = m[2], m[3], m[4]
        local erow, ecol = d.end_row or row, d.end_col or col
        for r = row, erow do
            local l = lines[r + 1] or ""
            local s = (r == row) and col or 0
            local e = (r == erow) and ecol or #l
            if e > s then
                table.insert(segs, { r, s, e, d.hl_group, l:sub(s + 1, e) })
            end
        end
    end
    table.sort(segs, function(a, b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        if a[2] ~= b[2] then return a[2] < b[2] end
        return a[4] < b[4]
    end)
    local out = {}
    for _, s in ipairs(segs) do
        table.insert(out, string.format("%d:%d-%d %s %s", s[1], s[2], s[3], s[4], s[5]))
    end
    return out
end

-- Contents of the floating windows, in window-id order.
function M.floats()
    local r = {}
    local wins = vim.api.nvim_list_wins()
    table.sort(wins)
    for _, w in ipairs(wins) do
        local cfg = vim.api.nvim_win_get_config(w)
        if cfg.relative ~= "" then
            table.insert(r, {
                win = w,
                width = cfg.width,
                lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, true),
            })
        end
    end
    return r
end

return M
