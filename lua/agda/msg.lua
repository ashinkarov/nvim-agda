-- Messages without the hit-enter prompt.
--
-- Neovim asks to press ENTER whenever a message needs more rows than
-- the command line has: a message with several lines (even just a
-- trailing newline) or a line wider than the screen.  It also does so
-- for separate messages given while a command runs, which scroll rather
-- than overwrite each other.  Most of what Agda sends is log-like, so
-- we instead add every line to the message history as a separate
-- message that fits on the screen, from a scheduled callback (where messages
-- overwrite each other), and end with a summary of the message that is
-- displayed but not added to the history.  The full text is in
-- :messages.  Messages can only be added to the history by displaying
-- them (:silent echomsg does not add them), hence the overwriting.
--
-- The new message UI (ui2, experimental in Neovim 0.12) has no
-- hit-enter prompt, so with it we simply echo the message.  Once ui2
-- is the default in the Neovim versions we support, remove `wrap`,
-- `layout`, `ui2_enabled` and everything in `show` but the ui2 branch,
-- and in tests/test_msg.lua the tests of the layout and of the old UI.

local M = {}

-- Whether the new message UI is enabled.  It does not show up in
-- nvim_list_uis(), so we ask its (internal) module, which sets `msg`
-- when it is enabled.  If this stops working, we fall back to the code
-- below, which works with ui2 too, but shows the summary in addition
-- to the lines of the message.
local function ui2_enabled()
    local ui2 = package.loaded["vim._core.ui2"]
    return ui2 ~= nil and ui2.msg ~= nil and ui2.cfg.enable ~= false
end

-- `msg` without leading empty lines and trailing whitespace (Agda's
-- messages often end with a newline).
local function trim(msg)
    return (msg:gsub("^\n+", ""):gsub("%s+$", ""))
end

-- `line` split into parts of at most `width` display cells (or one
-- character, if it is wider), at spaces where possible.
local function wrap(line, width)
    local parts = {}
    while vim.fn.strdisplaywidth(line) > width do
        local n = math.max(width, 1)
        while n > 1 and vim.fn.strdisplaywidth(vim.fn.strcharpart(line, 0, n)) > width do
            n = n - 1
        end
        local part = vim.fn.strcharpart(line, 0, n)
        local rest = line:sub(#part + 1)
        -- Break after the last space in the part, unless it is the
        -- next character anyway.
        local space = part:match(".*() ")
        if space and space > 1 and rest:sub(1, 1) ~= " " then
            rest = line:sub(space + 1)
            part = part:sub(1, space - 1)
        end
        table.insert(parts, (part:gsub("%s+$", "")))
        line = rest:gsub("^ +", "")
    end
    if line ~= "" or #parts == 0 then
        table.insert(parts, line)
    end
    return parts
end

-- The lines to add to the history for `msg`, at most `width` cells
-- each, and the summary to display afterwards (nil if the last line
-- that was added is the whole message).
function M.layout(msg, width)
    local lines = {}
    for l in vim.gsplit(trim(msg), "\n") do
        vim.list_extend(lines, wrap(l:gsub("%s+$", ""), width))
    end
    if #lines <= 1 then
        return lines, nil
    end
    local hint = string.format("  [+%d lines, see :messages]", #lines - 1)
    local first = lines[1]
    local room = width - vim.fn.strdisplaywidth(hint)
    if room < 2 then
        -- No room for the hint next to the line.
        return lines, {first, ""}
    elseif vim.fn.strdisplaywidth(first) > room then
        first = wrap(first, room - 1)[1] .. "…"
    end
    return lines, {first, hint}
end

-- Show `msg` with highlight group `hl` (optional).
function M.show(msg, hl)
    vim.schedule(function()
        if ui2_enabled() then
            vim.api.nvim_echo({{trim(msg), hl}}, true, {})
            return
        end
        -- v:echospace is the room for a message before it prompts, which
        -- is less than the width of the screen if the ruler or the
        -- partial command are shown in the command line.
        local lines, summary = M.layout(msg, vim.v.echospace)
        for _, l in ipairs(lines) do
            vim.api.nvim_echo({{l, hl}}, true, {})
        end
        if summary then
            vim.api.nvim_echo({{summary[1], hl}, {summary[2], "Comment"}}, false, {})
        end
    end)
end

return M
