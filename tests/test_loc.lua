local t = require("harness")
local Loc = require("agda.loc")

t.test("ordering within a line", function()
    t.ok(Loc:new(3, 1) < Loc:new(3, 2))
    t.ok(Loc:new(3, 2) <= Loc:new(3, 2))
    t.ok(not (Loc:new(3, 2) < Loc:new(3, 2)))
end)

t.test("ordering across lines ignores columns", function()
    t.ok(Loc:new(2, 99) < Loc:new(3, 1))
    t.ok(Loc:new(3, 1) > Loc:new(2, 99))
    t.ok(not (Loc:new(4, 1) <= Loc:new(3, 50)))
end)
