-- Code-point based string functions on top of Neovim's native API.
-- They replace the subset of the lua-utf8 library the plugin used to
-- depend on, with the same semantics: strings are sequences of code
-- points and composing characters count as separate code points, which
-- is also how Agda counts columns and offsets.

local M = {}

-- Number of code points in `s`.
function M.len(s)
    return vim.str_utfindex(s, "utf-32")
end

-- Byte position (1-based) where the `n`-th code point of `s` starts.
-- For n = len+1 this is #s+1; for anything beyond it is nil.
function M.offset(s, n)
    if n < 1 or n > M.len(s) + 1 then
        return nil
    end
    return vim.str_byteindex(s, "utf-32", n - 1, false) + 1
end

-- Substring from the `i`-th to the `j`-th code point (inclusive, default
-- to the end).  Negative indices count from the end, as in string.sub.
function M.sub(s, i, j)
    local l = M.len(s)
    j = j or -1
    if i < 0 then i = math.max(l + i + 1, 1) elseif i == 0 then i = 1 end
    if j < 0 then j = l + j + 1 elseif j > l then j = l end
    if i > j then
        return ""
    end
    return s:sub(vim.str_byteindex(s, "utf-32", i - 1, false) + 1,
                 vim.str_byteindex(s, "utf-32", j, false))
end

return M
