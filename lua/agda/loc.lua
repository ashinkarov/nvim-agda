-- Loc class
Loc = {}
Loc.__index = Loc

function Loc:new(l,c)
    local loc = {}
    setmetatable(loc,Loc)
    loc.line = l
    loc.col = c
    return loc
end

Loc.__le = function (l1, l2)
    if l1.line < l2.line then return true
    elseif l1.line == l2.line then return l1.col <= l2.col end
    return false
end

Loc.__lt = function (l1, l2)
    if l1.line < l2.line then return true
    elseif l1.line == l2.line then return l1.col < l2.col end
    return false
end

return Loc
