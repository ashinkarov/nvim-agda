-- Fake Agda process that replays a recorded transcript (see
-- tests/agda_helpers.lua for the format).  Started by tests/bin/agda as
--
--     nvim --clean --headless -l tests/replay.lua <agda args>
--
-- Every command read from stdin must match the next recorded command,
-- otherwise the mismatch is written to $AGDA_TEST_DIR/replay-error and
-- the process exits.  Responses are written in randomly sized chunks to
-- exercise the plugin's stream handling.

local dir = assert(vim.env.AGDA_TEST_DIR, "AGDA_TEST_DIR is not set")
local transcript = assert(vim.env.AGDA_TRANSCRIPT, "AGDA_TRANSCRIPT is not set")
local seed = tonumber(vim.env.AGDA_TEST_SEED) or os.time()
math.randomseed(seed)

local PROMPT = "JSON> "

local stdin_log = assert(io.open(dir .. "/stdin.log", "ab"))
local stdout_log = assert(io.open(dir .. "/stdout.log", "ab"))
io.stdout:setvbuf("no")

local function die(msg)
    local f = io.open(dir .. "/replay-error", "ab")
    if f then
        f:write(msg, "\n")
        f:close()
    end
    io.stderr:write("replay: ", msg, "\n")
    os.exit(1)
end

local fd = io.open(transcript, "rb")
if not fd then
    die("cannot open transcript " .. transcript)
end
local data = vim.json.decode(fd:read("*a"))
fd:close()

local function expand(s)
    return (s:gsub("%$DIR", (dir:gsub("%%", "%%%%"))))
end

local function normalise(s)
    return (s:gsub(vim.pesc(dir), "$DIR"))
end

-- Positions inside a prompt where we must not cut the stream.
-- FIXME: the current reader cannot cope with a prompt split across two
-- chunks; allow such cuts once the reader is fixed.
local function forbidden_cuts(s)
    local bad = {}
    local init = 1
    while true do
        local p = s:find(PROMPT, init, true)
        if not p then break end
        for i = p, p + #PROMPT - 2 do bad[i] = true end
        init = p + 1
    end
    return bad
end

local function emit(s)
    local bad = forbidden_cuts(s)
    local cuts = {}
    for _ = 1, math.random(0, math.min(#s - 1, 24)) do
        local c = math.random(1, #s - 1)
        if not bad[c] then cuts[c] = true end
    end
    local start = 1
    for i = 1, #s do
        if cuts[i] or i == #s then
            local chunk = s:sub(start, i)
            io.stdout:write(chunk)
            stdout_log:write(chunk)
            stdout_log:flush()
            start = i + 1
            vim.uv.sleep(2)
        end
    end
end

local exchanges = data.exchanges
emit(expand(exchanges[1][2]))

local i = 2
for line in io.stdin:lines() do
    if line ~= "" then
        stdin_log:write(line, "\n")
        stdin_log:flush()
        local ex = exchanges[i]
        if not ex then
            die("unexpected extra command: " .. normalise(line))
        end
        if normalise(line) ~= ex[1] then
            die("command mismatch\n  expected: " .. ex[1]
                .. "\n  got:      " .. normalise(line))
        end
        emit(expand(ex[2]))
        i = i + 1
    end
end
