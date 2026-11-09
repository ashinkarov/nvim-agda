-- Agda's errors, warnings and unsolved metas as Neovim diagnostics, so
-- that their messages can be shown at their places (CTRL-W d) and
-- visited (]d, [d).
--
-- There are two kinds of sources, kept apart here:
--
--   * Structured: places that Agda sends as data, which we only convert.
--     The error of a failed load comes as highlighting with the range of
--     the error and its message (`note`), unsolved metas come with their
--     ranges, and warnings would, if Agda sent a `range` with them.
--
--   * Mined: Agda sends warnings as text only ({"message": ...}, the
--     EncodeTCM TCWarning instance in src/full/Agda/Interaction/
--     JSONTop.hs, Agda 2.8.0), with the place at the start of the text,
--     in the format that Agda also uses on the command line:
--         /path/Problems.agda:12.1-14: error: [CoverageIssue]
--         Incomplete pattern matching for incomplete. ...
--     Only `parse_location` knows this format.  If it does not recognise
--     a message, the message gets no diagnostic (it is still shown in
--     the message area), so a change of the format can only make
--     diagnostics go missing.  The setting `diagnostics = "structured"`
--     turns the mining off (see the README), and doc/agda-upstream.md
--     proposes that Agda send the range with every warning.
--
-- The messages are shown as Agda sends them.

local M = {}

M.ns = vim.api.nvim_create_namespace("agda-diagnostics")
-- Agda's highlighting marks the places already.  With severity_sort,
-- the sign of a line is that of its most severe diagnostic rather than
-- of the last one.
vim.diagnostic.config({underline = false, severity_sort = true}, M.ns)

local severity = vim.diagnostic.severity

-- The severities of diagnostics by their code (Agda's name of the
-- warning, or "UnsolvedMeta"), or false for no diagnostic; the others
-- have Agda's level.  The setting `diagnostic_severity` changes them
-- (see `M.severities`).  Agda reports missing definitions as errors,
-- which they are not while a module is being written.
M.default_severities = {MissingDefinitions = "hint"}

local severity_names = {error = severity.ERROR, warn = severity.WARN,
                        info = severity.INFO, hint = severity.HINT}

-- The severities of the setting `user` (a table {code = "error",
-- "warn", "info", "hint" or false}) over the defaults, as {code =
-- severity or false}, and a message about the entries of `user` that
-- are not severities (which are left out), or nil.
function M.severities(user)
    local result = {}
    for code, s in pairs(M.default_severities) do
        result[code] = severity_names[s]
    end
    if user == nil then
        return result
    end
    if type(user) ~= "table" then
        return result, "the setting diagnostic_severity must be a table, not " .. vim.inspect(user)
    end
    local bad = {}
    for code, s in pairs(user) do
        if s == false then
            result[code] = false
        elseif type(code) == "string" and severity_names[s] then
            result[code] = severity_names[s]
        else
            table.insert(bad, vim.inspect(code) .. " = " .. vim.inspect(s))
        end
    end
    if #bad > 0 then
        table.sort(bad)
        return result, "the setting diagnostic_severity takes \"error\", \"warn\", \"info\", "
                       .. "\"hint\" or false for the names of warnings, not " .. table.concat(bad, ", ")
    end
    return result
end

-- `d` with the severity that `severities` (from `M.severities`) gives
-- its code, or nil if it gives false (or `d` is nil).
function M.adjust(d, severities)
    if d == nil or d.code == nil or severities[d.code] == nil then
        return d
    end
    if severities[d.code] == false then
        return nil
    end
    d.severity = severities[d.code]
    return d
end

-- The place and kind of an error or warning message of Agda, or nil if
-- the message does not start with a place that we recognise: {file =,
-- start = {line, col}, ["end"] = {line, col}, level = "error" or
-- "warning" or nil, name = e.g. "CoverageIssue" or nil}.  Lines and
-- columns are 1-based and count code points, the end is exclusive.  The
-- place is one of
--     file:line.col-line.col: ...
--     file:line.col-col: ...
--     file:line.col: ...
-- and is followed by "error: [Name]" or "warning: -W[no]Name", whose
-- name is "Name" (a file name may contain colons, e.g. C:\x.agda).
function M.parse_location(text)
    local first = text:match("^[^\n]*")
    local file, l1, c1, l2, c2, rest = first:match("^(.+):(%d+)%.(%d+)%-(%d+)%.(%d+): (.*)$")
    if file == nil then
        file, l1, c1, c2, rest = first:match("^(.+):(%d+)%.(%d+)%-(%d+): (.*)$")
        l2 = l1
    end
    if file == nil then
        file, l1, c1, rest = first:match("^(.+):(%d+)%.(%d+): (.*)$")
        l2, c2 = l1, c1 and tostring(tonumber(c1) + 1)
    end
    if file == nil then
        return nil
    end
    local level, name = rest:match("^(%a+): *(.-)%s*$")
    if level ~= "error" and level ~= "warning" then
        level, name = nil, nil
    end
    return {file = file,
            start = {tonumber(l1), tonumber(c1)},
            ["end"] = {tonumber(l2), tonumber(c2)},
            level = level,
            name = name and (name:match("^%[(.*)%]$") or name:match("^%-W%[no%](.*)$") or name)}
end

-- A diagnostic from `start` to `end_` ({0-based line, byte column} in
-- the buffer now), or nil if either is nil.
local function make(start, end_, sev, code, message)
    if start == nil or end_ == nil then
        return nil
    end
    return {lnum = start[1], col = start[2], end_lnum = end_[1], end_col = end_[2],
            severity = sev, code = code, message = message, source = "agda"}
end

-- `ctx` converts Agda's places: `ctx.pos(line, col)` gives the position
-- in the buffer now of a line and column of the text that Agda loaded
-- (1-based, in code points), or nil if it was edited since, and
-- `ctx.is_main(file)` says whether `file` is the file of the buffer.

-- Structured: the diagnostic of a range as Agda sends it in the json
-- ([{start = {line, col}, end = {line, col}}, ...]).
function M.from_range(range, ctx, sev, code, message)
    if type(range) ~= "table" or #range == 0 then
        return nil
    end
    local s, e = range[1].start, range[#range]["end"]
    return make(ctx.pos(s.line, s.col), ctx.pos(e.line, e.col), sev, code, message)
end

-- Structured: the diagnostic of the error of a failed load, from its
-- highlighting: the error's place in the buffer now and its message.
function M.from_error(start, end_, message)
    return make(start, end_, severity.ERROR, nil, message)
end

-- Structured: the diagnostic of an unsolved meta in AllGoalsWarnings,
-- with its description (e.g. "_5 : 𝔹").
function M.from_meta(goal, description, ctx)
    return M.from_range(goal.constraintObj and goal.constraintObj.range, ctx,
                        severity.WARN, "UnsolvedMeta", "Unsolved meta " .. description)
end

-- Mined: the diagnostic of a warning (or non-fatal error) of Agda,
-- {message = ...}, from its range if Agda sends one, or else from the
-- place at the start of its message if `mine`.
function M.from_warning(w, ctx, mine)
    local message = type(w) == "table" and w.message or w
    if type(message) ~= "string" then
        return nil
    end
    if type(w) == "table" and w.range ~= nil then
        return M.from_range(w.range, ctx, severity.WARN, nil, message)
    end
    if not mine then
        return nil
    end
    local ok, loc = pcall(M.parse_location, message)
    if not ok or loc == nil or not ctx.is_main(loc.file) then
        return nil
    end
    return make(ctx.pos(loc.start[1], loc.start[2]), ctx.pos(loc["end"][1], loc["end"][2]),
                loc.level == "warning" and severity.WARN or severity.ERROR,
                loc.name, message)
end

-- Show `list` (which may have holes where there was no diagnostic) in
-- buffer `buf`.
function M.set(buf, list)
    local ds = {}
    for _, d in pairs(list) do
        table.insert(ds, d)
    end
    vim.diagnostic.set(M.ns, buf, ds)
end

return M
