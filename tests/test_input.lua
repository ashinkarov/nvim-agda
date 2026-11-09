local t = require("harness")
local input = require("agda.input")

-- A sequence defined twice would silently replace the first definition.
t.test("no sequence is defined twice", function()
    local seen = {}
    for i, s in ipairs(input.sequences) do
        t.ok(seen[s[1]] == nil, string.format("\\%s is entry %d and %d", s[1], seen[s[1]] or 0, i))
        seen[s[1]] = i
    end
end)

-- Each sequence is typed as it is written (no spaces, and no
-- backslashes, which a mapping would take literally) and gives one
-- character (a trailing space would be inserted too).
t.test("sequences are plain and give one character", function()
    for _, s in ipairs(input.sequences) do
        t.ok(s[1] ~= "" and not s[1]:find("[%s\\]"), vim.inspect(s))
        t.ok(vim.fn.strchars(s[2]) == 1, vim.inspect(s))
    end
end)

-- The sequences are mappings in insert and command-line mode (searching
-- for symbols is useful) in the buffer only.
t.test("sequences are buffer-local mappings in insert and command-line mode", function()
    vim.cmd("enew")
    local buf = vim.api.nvim_get_current_buf()
    input.map(buf)
    for _, mode in ipairs({ "i", "c" }) do
        t.eq(#input.sequences, #vim.api.nvim_buf_get_keymap(buf, mode))
        t.eq("→", vim.fn.maparg("\\to", mode))
    end
    vim.cmd("enew")
    t.eq("", vim.fn.maparg("\\to", "i"))
    vim.api.nvim_buf_delete(buf, { force = true })
end)

local function typed(keys)
    vim.o.showmode = false
    vim.cmd("enew")
    input.map(0)
    vim.api.nvim_feedkeys(vim.keycode("i" .. keys .. "<Esc>"), "xt", false)
    local line = vim.api.nvim_get_current_line()
    vim.cmd("bwipe!")
    return line
end

-- \~ was replaced by a later line with ≋, \nin gave a trailing space and
-- ◬ needed a backslash in the sequence.
t.test("tilde, not in and the triangle with a dot", function()
    t.eq("∼", typed("\\~ "):sub(1, -2))
    t.eq("≋", typed("\\~~~"))
    t.eq("x∉y", typed("x\\niny"))
    t.eq("◬", typed("\\T.uw"))
end)

t.test("corner and half black triangles", function()
    t.eq("◢◿◣◺◤◸◥◹◭◮", typed("\\tdrb\\tdrw\\tdlb\\tdlw\\tulb\\tulw\\turb\\turw\\Tuhl\\Tuhr"))
end)

-- Subscript digits as in the Emacs mode, and without the underscore.
t.test("subscripts", function()
    t.eq("x₁₂₀₋₊₌₍₎", typed("x\\_1\\_2\\_0\\_-\\_+\\_=\\_(\\_)"))
    t.eq("x₁", typed("x\\1"))
end)
