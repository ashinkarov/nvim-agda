local t = require("harness")
local utf8 = require("agda.utf8")
local reference = dofile(t.root .. "/tests/utf8_reference.lua")

-- ASCII, 2/3/4-byte sequences, composing characters, CJK and the
-- characters that are typical for Agda code.
local strings = {
    "", "a", "ab", "λ", "→", "𝔹", "e\u{301}",
    "a→𝔹e\u{301}x",
    "{! x !}",
    "{! λ x → x !}",
    "id′ = λ x → ?",
    "pick 名前 y = ?",
    "∀ {ℓ} {A : Set ℓ} → A ≡ A",
}

local function check_against(impl, label)
    for _, s in ipairs(strings) do
        local l = impl.len(s)
        t.eq(impl.len(s), utf8.len(s), label .. " len " .. vim.inspect(s))
        for n = 1, l + 2 do
            t.eq(impl.offset(s, n), utf8.offset(s, n),
                 string.format("%s offset(%q, %d)", label, s, n))
        end
        for i = -l - 1, l + 2 do
            t.eq(impl.sub(s, i), utf8.sub(s, i),
                 string.format("%s sub(%q, %d)", label, s, i))
            for j = -l - 1, l + 2 do
                t.eq(impl.sub(s, i, j), utf8.sub(s, i, j),
                     string.format("%s sub(%q, %d, %d)", label, s, i, j))
            end
        end
    end
end

t.test("len counts code points", function()
    t.eq(0, utf8.len(""))
    t.eq(6, utf8.len("a→𝔹e\u{301}x"))   -- the composing accent counts separately
    t.eq(13, utf8.len("pick 名前 y = ?"))
end)

t.test("offset gives 1-based byte positions", function()
    local s = "a→𝔹x"
    t.eq({ 1, 2, 5, 9, 10 }, { utf8.offset(s, 1), utf8.offset(s, 2), utf8.offset(s, 3),
                               utf8.offset(s, 4), utf8.offset(s, 5) })
    t.eq(nil, utf8.offset(s, 6))
end)

t.test("sub extracts code point ranges", function()
    t.eq(" x ", utf8.sub("{! x !}", 3, -3))
    t.eq("名前", utf8.sub("pick 名前 y = ?", 6, 7))
    t.eq("?", utf8.sub("id′ = λ x → ?", 13, 13))
    t.eq("", utf8.sub("abc", 3, 2))
end)

t.test("char_index converts byte columns", function()
    local s = "pick 名前 y = ?"
    t.eq(1, utf8.char_index(s, 0))
    t.eq(6, utf8.char_index(s, 5))      -- 名
    t.eq(7, utf8.char_index(s, 8))      -- 前
    t.eq(13, utf8.char_index(s, #s - 1)) -- ?
    t.eq(1, utf8.char_index("", 0))
end)

t.test("agrees with the reference implementation", function()
    check_against(reference, "reference")
end)

t.test("agrees with lua-utf8 (if installed)", function()
    local ok, lib = pcall(require, "lua-utf8")
    if not ok then
        io.stdout:write("     (lua-utf8 not installed, skipped)\n")
        return
    end
    check_against(lib, "lua-utf8")
end)
