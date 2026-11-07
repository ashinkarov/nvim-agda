-- Pure-Lua stand-in for the subset of starwing/luautf8 that the plugin
-- uses (len, offset, sub).  The test runner loads it only when the real
-- `lua-utf8` C module cannot be found, so that the characterisation
-- tests can run on machines without the library installed.
--
-- Semantics follow luautf8 (which follows Lua 5.3's utf8 library):
-- strings are sequences of code points; composing characters count as
-- separate code points.

local M = {}

local function is_cont(b)
    return b >= 0x80 and b < 0xC0
end

-- Byte positions (1-based) at which code points start.
local function starts(s)
    local r = {}
    for i = 1, #s do
        if not is_cont(s:byte(i)) then
            r[#r + 1] = i
        end
    end
    return r
end

function M.len(s)
    return #starts(s)
end

-- Byte position where the n-th (n >= 1) code point starts; n = len+1
-- gives #s+1, anything beyond that gives nil.
function M.offset(s, n)
    assert(n >= 1, "shim only supports positive offsets")
    local st = starts(s)
    if n <= #st then
        return st[n]
    elseif n == #st + 1 then
        return #s + 1
    end
    return nil
end

-- Code-point substring with Lua-style index normalisation.
function M.sub(s, i, j)
    local st = starts(s)
    local l = #st
    j = j or -1
    if i < 0 then i = math.max(l + i + 1, 1) elseif i == 0 then i = 1 end
    if j < 0 then j = l + j + 1 elseif j > l then j = l end
    if i > j then
        return ""
    end
    local e = (j < l) and st[j + 1] - 1 or #s
    return s:sub(st[i], e)
end

return M
