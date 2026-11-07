-- Test runner.  Usage:
--
--     nvim --clean --headless -l tests/run.lua [pattern]
--
-- Runs every tests/test_*.lua file (optionally only the cases whose
-- "file: name" matches the Lua pattern) and exits with a non-zero
-- status if any case fails.

local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(
    debug.getinfo(1, "S").source:sub(2))))
root = vim.fn.fnamemodify(root, ":p"):gsub("/$", "")

vim.opt.rtp:prepend(root)
package.path = root .. "/tests/?.lua;" .. package.path

-- Use the real lua-utf8 if it is installed (system-wide or with
-- `luarocks install --local --lua-version=5.1 luautf8`), the shim otherwise.
package.cpath = package.cpath .. ";" .. vim.fn.expand("~/.luarocks/lib/lua/5.1/?.so")
if not pcall(require, "lua-utf8") then
    package.preload["lua-utf8"] = function()
        return dofile(root .. "/tests/shim/lua-utf8.lua")
    end
end

local harness = require("harness")
harness.root = root

local filter = _G.arg[1]
local failures, passed = 0, 0

for _, file in ipairs(vim.fn.glob(root .. "/tests/test_*.lua", false, true)) do
    harness.cases = {}
    dofile(file)
    local fname = vim.fn.fnamemodify(file, ":t:r")
    for _, case in ipairs(harness.cases) do
        local full = fname .. ": " .. case.name
        if not filter or full:match(filter) then
            local ok, err = xpcall(case.fn, debug.traceback)
            if harness.after_each then
                local ok2, err2 = xpcall(harness.after_each, debug.traceback)
                if ok and not ok2 then ok, err = ok2, err2 end
            end
            if ok then
                passed = passed + 1
                io.stdout:write("ok   ", full, "\n")
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
