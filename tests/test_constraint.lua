local t = require("harness")
local constraint = require("agda.constraint")

local function range(l1, c1, l2, c2)
    return { { start = { line = l1, col = c1 }, ["end"] = { line = l2, col = c2 } } }
end

-- The objects as Agda 2.8.0 sends them.
t.test("goals and metas", function()
    t.eq("?0 : 𝔹", constraint.show({ kind = "OfType", type = "𝔹",
                                     constraintObj = { id = 0, range = range(22, 5, 22, 6) } }))
    t.eq("_5 : 𝔹  [at 8.9-10]",
         constraint.show_at({ kind = "OfType", type = "𝔹",
                              constraintObj = { name = "_5" } }, range(8, 9, 8, 10)))
    t.eq("Sort _3", constraint.show({ kind = "JustSort", constraintObj = { name = "_3" } }))
    t.eq("Type x  [at 1.2-3.4]",
         constraint.show_at({ kind = "JustType", constraintObj = "x" }, range(1, 2, 3, 4)))
end)

t.test("constraints", function()
    t.eq("G _x_13 = tt : 𝔹",
         constraint.show({ kind = "CmpInType", comparison = "CmpEq", type = "𝔹",
                           constraintObjs = { "G _x_13", "tt" } }))
    t.eq("_14 := q", constraint.show({ kind = "Assign", constraintObj = "_14", value = "q" }))
    t.eq("Set =< Set₁", constraint.show({ kind = "CmpSorts", comparison = "CmpLeq",
                                          constraintObjs = { "Set", "Set₁" } }))
    t.eq("f x [Invariant] f y : A",
         constraint.show({ kind = "CmpElim", polarities = { "Invariant" }, type = "A",
                           constraintObjs = { { "f", "x" }, { "f", "y" } } }))
    t.eq("_1 := (_ : A) a (b c) : B",
         constraint.show({ kind = "PostponedCheckArgs", constraintObj = "_1", ofType = "A",
                           arguments = { "a", "b c" }, type = "B" }))
    t.eq("Resolve instance argument _2 : Eq A\n  Candidates:\n    eqA : Eq A",
         constraint.show({ kind = "FindInstanceOF", constraintObj = "_2", type = "Eq A",
                           candidates = { { value = "eqA", type = "Eq A" } } }))
end)

t.test("unknown kinds are shown with their fields", function()
    local text = constraint.show({ kind = "NewKind", x = 1 })
    t.ok(text:find("NewKind", 1, true) and text:find("x = 1", 1, true), text)
end)
