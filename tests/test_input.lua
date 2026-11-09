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
