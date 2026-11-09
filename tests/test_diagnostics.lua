local t = require("harness")
local diag = require("agda.diagnostics")

-- Places in the loaded text are positions in the buffer: line - 1 and
-- col - 1 (no edits, ASCII), in the file /m/M.agda.
local ctx = {
    pos = function(line, col) return { line - 1, col - 1 } end,
    is_main = function(file) return file == "/m/M.agda" end,
}

-- The formats of places in Agda 2.8.0's messages.
t.test("places in messages", function()
    t.eq({ file = "/m/M.agda", start = { 12, 1 }, ["end"] = { 12, 14 },
           level = "error", name = "CoverageIssue" },
         diag.parse_location("/m/M.agda:12.1-14: error: [CoverageIssue]\nIncomplete pattern matching"))
    t.eq({ file = "/m/M.agda", start = { 6, 1 }, ["end"] = { 7, 10 },
           level = "error", name = "TerminationIssue" },
         diag.parse_location("/m/M.agda:6.1-7.10: error: [TerminationIssue]\n..."))
    t.eq({ file = "/m/M.agda", start = { 17, 1 }, ["end"] = { 17, 20 },
           level = "warning", name = "UnreachableClauses" },
         diag.parse_location("/m/M.agda:17.1-20: warning: -W[no]UnreachableClauses\nUnreachable clause"))
    t.eq({ file = "/m/M.agda", start = { 3, 4 }, ["end"] = { 3, 5 } },
         diag.parse_location("/m/M.agda:3.4: something else"))
    -- File names with colons and spaces.
    t.eq("C:\\a b\\M.agda", diag.parse_location("C:\\a b\\M.agda:1.1-2: error: [X]").file)
end)

-- Anything else gives no place, rather than a wrong one.
t.test("messages without places", function()
    t.eq(nil, diag.parse_location("error: [UnsolvedConstraints]\nFailed to solve the following constraints:"))
    t.eq(nil, diag.parse_location("1.1: error: [ParseError]"))
    t.eq(nil, diag.parse_location("M.agda:12: error: [X]"))
    t.eq(nil, diag.parse_location(""))
    t.eq(nil, diag.from_warning({ message = "Some new format: at line 3" }, ctx, true))
    t.eq(nil, diag.from_warning({ message = 42 }, ctx, true))
    t.eq(nil, diag.from_warning({}, ctx, true))
end)

t.test("warnings from their messages", function()
    local msg = "/m/M.agda:12.1-14: error: [CoverageIssue]\nIncomplete pattern matching"
    t.eq({ lnum = 11, col = 0, end_lnum = 11, end_col = 13, severity = vim.diagnostic.severity.ERROR,
           code = "CoverageIssue", message = msg, source = "agda" },
         diag.from_warning({ message = msg }, ctx, true))
    -- Only when mining, and only for the file of the buffer.
    t.eq(nil, diag.from_warning({ message = msg }, ctx, false))
    t.eq(nil, diag.from_warning({ message = msg:gsub("/m/M", "/m/Other") }, ctx, true))
end)

-- A range sent with a warning (which Agda 2.8.0 does not do) is used
-- rather than the message, also when not mining.
t.test("warnings with ranges", function()
    local w = { message = "/m/M.agda:1.1-2: error: [X]",
                range = { { start = { line = 3, col = 2 }, ["end"] = { line = 3, col = 5 } } } }
    for _, mine in ipairs({ true, false }) do
        local d = diag.from_warning(w, ctx, mine)
        t.eq({ 2, 1, 2, 4 }, { d.lnum, d.col, d.end_lnum, d.end_col })
    end
end)

t.test("unsolved metas and edited places", function()
    local goal = { kind = "OfType", type = "𝔹", constraintObj = { name = "_5",
        range = { { start = { line = 8, col = 9 }, ["end"] = { line = 8, col = 10 } } } } }
    local d = diag.from_meta(goal, "_5 : 𝔹", ctx)
    t.eq({ 7, 8, 7, 9, "UnsolvedMeta", "Unsolved meta _5 : 𝔹" },
         { d.lnum, d.col, d.end_lnum, d.end_col, d.code, d.message })
    local edited = { pos = function() return nil end, is_main = ctx.is_main }
    t.eq(nil, diag.from_meta(goal, "_5 : 𝔹", edited))
    t.eq(nil, diag.from_meta({ constraintObj = { name = "_6", range = {} } }, "_6 : 𝔹", ctx))
end)

t.test("severities by the names of warnings", function()
    local S = vim.diagnostic.severity
    t.eq({ MissingDefinitions = false }, diag.severities(nil))
    t.eq({ MissingDefinitions = false, UnsolvedMeta = S.INFO },
         diag.severities({ MissingDefinitions = false, UnsolvedMeta = "info" }))
    -- Wrong entries are left out and reported.
    local s, problem = diag.severities({ CoverageIssue = "warning", UnsolvedMeta = "error" })
    t.eq({ MissingDefinitions = false, UnsolvedMeta = S.ERROR }, s)
    t.eq('the setting diagnostic_severity takes "error", "warn", "info", "hint" or false '
         .. 'for the names of warnings, not "CoverageIssue" = "warning"', problem)
    t.eq('the setting diagnostic_severity must be a table, not "hint"',
         select(2, diag.severities("hint")))

    local function d(code) return { code = code, severity = S.ERROR } end
    t.eq(nil, diag.adjust(d("MissingDefinitions"), diag.severities(nil)))
    t.eq(S.HINT, diag.adjust(d("MissingDefinitions"), { MissingDefinitions = S.HINT }).severity)
    t.eq(S.ERROR, diag.adjust(d("CoverageIssue"), diag.severities(nil)).severity)
    t.eq(S.ERROR, diag.adjust(d(nil), diag.severities(nil)).severity)
    t.eq(nil, diag.adjust(d("UnsolvedMeta"), { UnsolvedMeta = false }))
    t.eq(nil, diag.adjust(nil, {}))
end)
