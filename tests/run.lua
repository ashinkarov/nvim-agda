-- Test runner.  Usage:
--
--     nvim --clean --headless -l tests/run.lua [pattern]
--
-- Runs every tests/test_*.lua file (optionally only the cases whose
-- "file: name" matches one of the "|"-separated Lua patterns) and exits
-- with a non-zero status if any case fails.

local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(
    debug.getinfo(1, "S").source:sub(2))))
root = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")

vim.opt.rtp:prepend(root)
vim.cmd("filetype plugin on")
-- Filetype detection already ran before `root` was on the runtimepath.
vim.cmd("augroup filetypedetect | runtime! ftdetect/*.vim | augroup END")
package.path = root .. "/tests/?.lua;" .. package.path

-- Make lua-utf8 available when installed with
-- `luarocks install --local --lua-version=5.1 luautf8`; tests/test_utf8.lua
-- then also compares against it.
package.cpath = package.cpath .. ";" .. vim.fn.expand("~/.luarocks/lib/lua/5.1/?.so")

local harness = require("harness")
harness.root = root

local filters = _G.arg[1] and vim.split(_G.arg[1], "|", { plain = true })

local function selected(name)
    if not filters then
        return true
    end
    for _, f in ipairs(filters) do
        if name:match(f) then
            return true
        end
    end
    return false
end
local failures, passed = 0, 0

for _, file in ipairs(vim.fn.glob(root .. "/tests/test_*.lua", false, true)) do
    harness.cases = {}
    dofile(file)
    local fname = vim.fn.fnamemodify(file, ":t:r")
    for _, case in ipairs(harness.cases) do
        local full = fname .. ": " .. case.name
        if selected(full) then
            local t0 = vim.uv.hrtime()
            local ok, err = xpcall(case.fn, debug.traceback)
            if harness.after_each then
                local ok2, err2 = xpcall(harness.after_each, debug.traceback)
                if ok and not ok2 then ok, err = ok2, err2 end
            end
            if ok then
                passed = passed + 1
                io.stdout:write(string.format("ok   %s (%.1fs)\n", full, (vim.uv.hrtime() - t0) / 1e9))
            else
                failures = failures + 1
                io.stdout:write("FAIL ", full, "\n", err, "\n")
            end
        end
    end
    harness.after_each = nil
end

io.stdout:write(string.format("\n%d passed, %d failed\n", passed, failures))
os.exit(failures > 0 and 1 or 0)
