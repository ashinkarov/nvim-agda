-- Minimal test framework: registration and assertions.
local M = {}

M.cases = {}

-- Register a test case.  Cases run in the order they are registered.
function M.test(name, fn)
    table.insert(M.cases, { name = name, fn = fn })
end

local function fail(msg, level)
    error(msg, (level or 1) + 2)
end

function M.eq(expected, actual, what)
    if not vim.deep_equal(expected, actual) then
        fail(string.format("%sexpected %s, got %s",
            what and (what .. ": ") or "",
            vim.inspect(expected), vim.inspect(actual)))
    end
end

function M.ok(v, what)
    if not v then
        fail(what or "expected a truthy value")
    end
    return v
end

-- Compare `lines` with tests/golden/<name>.txt.  With UPDATE_GOLDEN=1 the
-- file is (re)written instead.
function M.golden(name, lines)
    local path = M.root .. "/tests/golden/" .. name .. ".txt"
    if vim.env.UPDATE_GOLDEN == "1" then
        vim.fn.mkdir(vim.fs.dirname(path), "p")
        vim.fn.writefile(lines, path)
        return
    end
    if vim.fn.filereadable(path) == 0 then
        fail("missing golden file " .. path .. " (run with UPDATE_GOLDEN=1)")
    end
    local expected = vim.fn.readfile(path)
    if not vim.deep_equal(expected, lines) then
        local diff = (vim.text.diff or vim.diff)(table.concat(expected, "\n") .. "\n",
                                   table.concat(lines, "\n") .. "\n")
        fail("output differs from golden/" .. name .. ".txt:\n" .. diff)
    end
end

return M
