-- Printing of the constraints that Agda sends: the goals in
-- AllGoalsWarnings and the result of Cmd_constraints.
--
-- Agda sends them as structures rather than as text (`encodeOC` in
-- src/full/Agda/Interaction/JSONTop.hs), so we print them like Agda's
-- pretty printer does (the Pretty instance of OutputConstraint in
-- src/full/Agda/Interaction/BasicOps.hs, Agda 2.8.0).

local M = {}

local comparisons = { CmpEq = "=", CmpLeq = "=<" }

-- A constraint object: a goal ({id = n}, printed as ?n), a meta
-- ({name = "_5"}), an expression (a string), or a list of them.
function M.obj(o)
    if type(o) ~= "table" then
        return tostring(o)
    elseif o.id ~= nil then
        return "?" .. o.id
    elseif o.name ~= nil then
        return o.name
    end
    return table.concat(vim.tbl_map(M.obj, o), " ")
end

-- A range as Agda prints it in messages (line.col-col or
-- line.col-line.col), or nil if it is empty.
function M.range(r)
    if r == nil or #r == 0 then
        return nil
    end
    local s, e = r[1].start, r[#r]["end"]
    if s.line == e.line then
        return string.format("%d.%d-%d", s.line, s.col, e.col)
    end
    return string.format("%d.%d-%d.%d", s.line, s.col, e.line, e.col)
end

local function cmp(c)
    return string.format("%s %s %s", M.obj(c.constraintObjs[1]),
                         comparisons[c.comparison] or c.comparison,
                         M.obj(c.constraintObjs[2]))
end

-- Arguments are parenthesised if they contain spaces.
local function paren(e)
    return e:find("[ \n]") and ("(" .. e .. ")") or e
end

local printers = {
    OfType = function (c) return M.obj(c.constraintObj) .. " : " .. c.type end,
    JustType = function (c) return "Type " .. M.obj(c.constraintObj) end,
    JustSort = function (c) return "Sort " .. M.obj(c.constraintObj) end,
    CmpInType = function (c) return cmp(c) .. " : " .. c.type end,
    CmpElim = function (c)
        return string.format("%s [%s] %s : %s", M.obj(c.constraintObjs[1]),
                             table.concat(c.polarities, ", "),
                             M.obj(c.constraintObjs[2]), c.type)
    end,
    CmpTypes = cmp,
    CmpLevels = cmp,
    CmpTeles = cmp,
    CmpSorts = cmp,
    Assign = function (c) return M.obj(c.constraintObj) .. " := " .. c.value end,
    TypedAssign = function (c)
        return string.format("%s := %s :? %s", M.obj(c.constraintObj), c.value, c.type)
    end,
    PostponedCheckArgs = function (c)
        local args = table.concat(vim.tbl_map(paren, c.arguments), " ")
        return string.format("%s := (_ : %s) %s : %s", M.obj(c.constraintObj),
                             c.ofType, args, c.type)
    end,
    IsEmptyType = function (c) return "Is empty: " .. c.type end,
    SizeLtSat = function (c) return "Not empty type of sizes: " .. c.type end,
    FindInstanceOF = function (c)
        local lines = { string.format("Resolve instance argument %s : %s",
                                      M.obj(c.constraintObj), c.type),
                        "  Candidates:" }
        for _, cand in ipairs(c.candidates) do
            table.insert(lines, string.format("    %s : %s", cand.value, cand.type))
        end
        return table.concat(lines, "\n")
    end,
    ResolveInstanceOF = function (c) return "Resolve output type of instance " .. c.name end,
    PTSInstance = function (c)
        return string.format("PTS instance for (%s, %s)", M.obj(c.constraintObjs[1]),
                             M.obj(c.constraintObjs[2]))
    end,
    PostponedCheckFunDef = function (c)
        return string.format("Check definition of %s : %s", c.name, c.type)
    end,
    DataSort = function (c)
        return string.format("Sort %s allows data/record definitions", M.obj(c.sort))
    end,
    CheckLock = function (c)
        return string.format("Check lock %s allows %s", M.obj(c.lock), M.obj(c.head))
    end,
    UsableAtMod = function (c)
        return string.format("Is usable at %s modality: %s", c.mod, M.obj(c.term))
    end,
}

-- `c` as text, which may have several lines.  Kinds that we do not know
-- are shown with their fields, so that nothing is lost.
function M.show(c)
    local p = printers[c.kind]
    if p == nil then
        return vim.inspect(c, { newline = " ", indent = "" })
    end
    return p(c)
end

-- `c` followed by `range` if it is not empty.
function M.show_at(c, range)
    local r = M.range(range)
    return M.show(c) .. (r and ("  [at " .. r .. "]") or "")
end

return M
