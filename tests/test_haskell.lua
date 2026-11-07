local t = require("harness")
local haskell = require("agda.haskell")

t.test("haskell string literals", function()
    local cases = {
        { "", '""' },
        { "λ x → x", '"λ x → x"' },
        { 'a"b', '"a\\"b"' },
        { "a\\b", '"a\\\\b"' },
        { "a\nb\tc", '"a\\nb\\tc"' },
        -- \& keeps the following digit out of the escape (\271 is ı).
        { "\0271", '"\\27\\&1"' },
        { "\0\r\127", '"\\0\\&\\13\\&\\127\\&"' },
        { "/tmp/we\"ird\\dir/A.agda", '"/tmp/we\\"ird\\\\dir/A.agda"' },
    }
    for _, c in ipairs(cases) do
        t.eq(c[2], haskell.string(c[1]), vim.inspect(c[1]))
    end
end)
