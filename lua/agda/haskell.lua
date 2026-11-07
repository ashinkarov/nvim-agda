-- Agda reads commands with Haskell's `reads` (`parseIOTCM` in Agda's
-- src/full/Agda/Interaction/Base.hs), so strings in commands have to be
-- Haskell string literals.  Json strings are not: json writes control
-- characters as \u001B, which Haskell does not accept.

local M = {}

local escapes = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\t'] = '\\t' }

-- `s` as a Haskell string literal, including the quotes.  Non-ASCII
-- characters are kept as they are, Agda reads its input as UTF-8.
function M.string(s)
    local quoted = s:gsub('[%c"\\]', function(c)
        -- Other control characters become decimal escapes, followed by
        -- the empty escape \& so that a digit after them is not read as
        -- part of the number.
        return escapes[c] or ('\\' .. string.byte(c) .. '\\&')
    end)
    return '"' .. quoted .. '"'
end

return M
