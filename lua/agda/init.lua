local utf8 = require('agda.utf8')
local Loc = require('agda.loc')
local haskell = require('agda.haskell')
local constraint = require('agda.constraint')
local messages = require('agda.msg')

local M = {}
-- Different for every instance of the module (the ftplugin creates one
-- per buffer, and a new one when it runs again).
M.instance = tostring(M)

------ State Variable ------
----------------------------

-- Agda Process Handle.  Created by `agda_start`.
local agda_bin = "agda"
local agda_args = {}

local agda_job = nil

-- Agda version
local agda_major = 0
local agda_minor = 0
local agda_patch = 0

-- The list of goals in the format {id = {start = {l,c}, end = {l,c}}}
-- l and c are 1-based line and column as it is given by agda.
local goals = {}

-- Handles for the (vim)window and (vim)buffer that we use in
-- `mk_window` to display popups.
local msg_buf = nil
local msg_win = nil
local msg_min_width = 25

-- The incomplete last line of Agda's output so far.
-- See `on_event` for the details on the usage.
local evbuf = ""

-- Variables to set continuation to be run by handle_interpoints
-- after updating the list of goals.
local sfunc = nil
local sargs = nil

local error_count = 0

-- The scope of the last why-in-scope command ("at the top level" or "in
-- goal ?n"), for the header of the answer, which does not say.
local why_scope = nil

-- The buffer of the Agda file.  There is one instance of this module
-- per buffer, created by the ftplugin.
local main_buf = vim.api.nvim_get_current_buf()
-- The file name that we last loaded the buffer as.
local main_file = nil

-- Content and line-offset structure for handling
-- highlighting.
local main_content = ""
local main_lines = {}

-- Prompt window and buffer
local pwin = nil
local pbuf = nil
-- The goal that the goal-edit window edits.
local pgoal = nil
local pmin_width = 25

-- Whether to print debug information
local debug_p = false

-- Highlighting namespace.
local hl_ns = vim.api.nvim_create_namespace("agda-hl-ns")
-- The extmarks in `hl_ns` by the range they highlight ("start-end"
-- offsets as sent by Agda), a list for every range.
local hl_marks = {}
-- The names in the highlighting, by the first extmark of their range:
-- {filepath, position, operator} with the definition site of the name as
-- Agda sends it, and whether it is (part of) an operator.  A flat table,
-- as there are many: about 10000 in a 2500-line file.  The extmarks move with edits, so the
-- name under the cursor can be found after the buffer was changed.
local hl_names = {}
-- The first extmark of the range that starts at an offset, for the names
-- in `hl_names`, to find definitions in this file after edits.
local hl_name_at = {}


------ Helper functions ------
------------------------------

-- Messages go through `agda.msg`, which avoids the hit-enter prompt;
-- the full text is in :messages.
local function display(msg)
    messages.show(msg)
end

local function show_error(msg)
    messages.show(msg, "ErrorMsg")
end

local function warning(msg)
    display("Warning: " .. msg)
end

local function prefix(p, s)
    return p == string.sub(s, 1, #p)
end

local function len(t)
    local l = 0
    for _,_ in pairs(t) do
        l = l + 1
    end
    return l
end

-- Show the arguments if `debug_p` is set; tables are inspected.
local function dprint(...)
    if debug_p then
        display(table.concat(vim.tbl_map(function (x)
            return type(x) == "string" and x or vim.inspect(x)
        end, {...}), "\t"))
    end
end

-- Display width of a string in screen cells.
local function width(s)
    return vim.api.nvim_strwidth(s)
end

-- Either a list of lines (key=nil), or the list of objects
-- and we are interested in the field "key".
local function max_width(lines,key)
    local max = 0
    for _,v in pairs(lines) do
        if key ~= nil then
            v = v[key]
        end
        max = math.max(max, width(v))
    end
    return max
end

-- A separator line in the content of a popup; `mk_window` draws it as
-- wide as the window.
local SEP = "\0SEP"

local function split_lines(s)
    return vim.split(s, "\n")
    -- local ls = {}
    -- for l in string.gmatch(s, "[^\n]+") do
    --     table.insert(ls, l)
    -- end
    -- return ls
end

local function main_buf_changed()
    for _,v in pairs(vim.fn.getbufinfo()) do
        if v.bufnr == main_buf then
            return v.changed
        end
    end
    return nil
end

-- The window showing the main buffer: the current window if it does,
-- otherwise any window in the current tab that does, or nil.
local function main_window()
    if vim.api.nvim_get_current_buf() == main_buf then
        return vim.api.nvim_get_current_win()
    end
    local w = vim.fn.bufwinid(main_buf)
    return w ~= -1 and w or nil
end

-- Position of `loc` in the main buffer as {0-based line, byte column},
-- the format of `bufpos` in `nvim_open_win`.
local function buf_pos(loc)
    local line = vim.api.nvim_buf_get_lines(main_buf, loc.line-1, loc.line, true)[1]
    return {loc.line-1, (utf8.offset(line, loc.col) or #line + 1) - 1}
end

-- Agda counts columns in code points, whereas virtcol counts screen
-- cells, so we convert the byte column of the cursor.
local function get_current_loc()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local line = vim.api.nvim_get_current_line()
    return Loc:new(cursor[1], utf8.char_index(line, cursor[2]))
end

------ Agda interaction-related functions ------
------------------------------------------------

function M.setup(config)
    -- Stop Agda when the buffer is unloaded: when it is loaded again the
    -- ftplugin creates a new instance of this module anyway.  The group
    -- is per buffer and replaced when the ftplugin runs again.
    vim.api.nvim_create_autocmd("BufUnload", {
        group = vim.api.nvim_create_augroup("agda_buf_" .. main_buf, {clear = true}),
        buffer = main_buf,
        callback = function () M.agda_stop() end,
    })
    if not config then
        return
    end
    if config.agda then   agda_bin = config.agda  end
    if config.agda_args then agda_args = config.agda_args end
    if config.debug_p then debug_p = config.debug_p end
end

function M.close_prompt_win()
    if pwin ~= nil and vim.api.nvim_win_is_valid(pwin) then
        vim.api.nvim_win_close(pwin, true)
    end
    pwin = nil
end

-- goal is a pair <id:int, {start:Loc, end:Loc}>
local function mk_prompt_window(file, goal)
    M.close_prompt_win()
    pgoal = goal[1]
    if pbuf == nil then
        pbuf = vim.api.nvim_create_buf(false, true)
        -- load unicode mappings.
        vim.api.nvim_buf_call(pbuf, function () vim.cmd("runtime agda-input.vim") end)
    end

    local status = {silent=true, nowait=true, noremap=true}
    local function mk_mapping(key, fun, args)
        vim.api.nvim_buf_set_keymap(
            pbuf, 'n', key,
            ":call getbufvar(" .. main_buf .. ", 'AgdaMod')." .. fun .. "(" .. args .. ")<cr>",
            status)
    end
    mk_mapping("<LocalLeader>,", "agda_type_context",       string.format("'%s', 'Simplified', %d", file, goal[1]))
    mk_mapping("<LocalLeader>.", "agda_type_context_infer", string.format("'%s', 'Simplified', %d", file, goal[1]))
    mk_mapping("<LocalLeader>d", "agda_infer",              string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>c", "agda_make_case",          string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>r", "agda_refine",             string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>m", "agda_elaborate_give",     string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>n", "agda_compute",            string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>a", "agda_auto",               string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>s", "agda_solve",              string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>h", "agda_helper_fun",         string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>q", "close_msg_win",           "")
    mk_mapping("q",              "close_prompt_win",        "")

    -- Just below the line of the goal, starting in its column.
    pwin = vim.api.nvim_open_win(
        pbuf, true,
        {
            relative='win',
            win=main_window(),
            bufpos=buf_pos(goal[2].start),
            row=1,
            col=0,
            width=pmin_width,
            height=1,
            style="minimal",
            anchor="SW"
        })

end


-- Show message window.  `loc:Loc` is the location of the goal
-- in the file.  If `loc` is omitted, the window is shown at
-- the current position of the cursor.
local function mk_window(lines,loc)
    if msg_buf == nil then
        msg_buf = vim.api.nvim_create_buf(false, true)
        -- Forget `msg_win` when the window is closed by other means than
        -- `close_msg_win`, e.g. with :q.
        vim.api.nvim_create_autocmd("WinClosed", {
            buffer = msg_buf,
            callback = function (args)
                if tonumber(args.match) == msg_win then
                    msg_win = nil
                end
            end
        })
        local status = {silent=true, nowait=true, noremap=true}
        local function mk_mappingx(key, fun, args)
            vim.api.nvim_buf_set_keymap(
                msg_buf, 'n', key,
                ":call getbufvar(" .. main_buf .. ", 'AgdaMod')." .. fun .. "(" .. args .. ")<cr>",
                status)
        end
        mk_mappingx("<LocalLeader>q", "close_msg_win",  "")
        mk_mappingx("q",              "close_msg_win",  "")
    end

    -- As wide as the content, but at most as wide as the screen; longer
    -- lines wrap, so the height counts the screen lines they take.
    local w = 0
    for _, l in ipairs(lines) do
        if l ~= SEP then w = math.max(w, width(l)) end
    end
    w = math.min(math.max(w, msg_min_width), vim.o.columns)
    local h = 0
    for i, l in ipairs(lines) do
        if l == SEP then
            lines[i] = string.rep("─", w)
            h = h + 1
        else
            h = h + math.max(1, math.ceil(width(l) / w))
        end
    end
    vim.api.nvim_buf_set_lines(msg_buf, 0, -1, true, lines)

    M.close_msg_win()

    local state = {
        width=w,
        height=h,
        style="minimal"
    }
    local win = loc and main_window()
    if win == nil then
        state.relative='cursor'
        state.row=1
        state.col=1
    else
        state.relative = 'win'
        state.win = win
        -- We know that goal defines a position that has to
        -- exist in the buffer, therefore we can use it to
        -- position the window.
        state.bufpos = buf_pos(loc)
    end

    --print("mk_win: l="..(l or "nil")..", ".."c="..(c or "nil").."; "..vim.inspect(state))
    msg_win = vim.api.nvim_open_win(msg_buf, false, state)
end

function M.close_msg_win()
    if msg_win ~= nil and vim.api.nvim_win_is_valid(msg_win) then
        vim.api.nvim_win_close(msg_win, true)
    end
    msg_win = nil
end


-- Convert a (1-based, code point) offset into the file, as Agda sends
-- them, into a {0-based line, byte column} position in the main buffer
-- as it was loaded, by binary search in the line offsets.
local function offset_pos(offset)
    local lo, hi = 1, #main_lines
    while lo <= hi do
        local i = math.floor((lo + hi) / 2)
        if offset < main_lines[i][1] then
            hi = i - 1
        elseif offset > main_lines[i][2] then
            lo = i + 1
        else
            return {i-1, utf8.offset(main_content[i], offset-main_lines[i][1]+1)-1}
        end
    end
end

-- The highlight groups of the atoms in Agda's highlighting: the aspects
-- and kinds of names, then the other aspects (src/full/Agda/Syntax/
-- Common/Aspect.hs and `toAtoms` in src/full/Agda/Interaction/
-- Highlighting/Common.hs, Agda 2.8.0).  Atoms that are not here, such
-- as `symbol`, `operator`, `typechecks` and `dottedpattern`, are not
-- highlighted.  The ftplugin defines the groups starting with Agda.
local hl_groups = {
    comment = "Comment",
    keyword = "Keyword",
    string = "String",
    number = "Number",
    hole = "AgdaHole",
    primitivetype = "Type",
    pragma = "PreProc",
    bound = "Identifier",
    generalizable = "Identifier",
    argument = "Identifier",
    inductiveconstructor = "Constant",
    coinductiveconstructor = "Constant",
    datatype = "Type",
    record = "Type",
    field = "Identifier",
    ["function"] = "Operator",
    macro = "Macro",
    module = "Structure",
    postulate = "PreProc",
    primitive = "PreProc",

    error = "Error",
    errorwarning = "AgdaErrorWarning",
    unsolvedmeta = "AgdaUnsolvedMeta",
    unsolvedconstraint = "AgdaUnsolvedConstraint",
    terminationproblem = "NonTerminating",
    positivityproblem = "AgdaPositivityProblem",
    deadcode = "AgdaDeadcode",
    shadowingintelescope = "AgdaShadowingInTelescope",
    coverageproblem = "AgdaCoverageProblem",
    incompletepattern = "AgdaIncompletePattern",
    missingdefinition = "NoDefinition",
    instanceproblem = "AgdaInstanceProblem",
    cosmeticproblem = "AgdaCosmeticProblem",
    catchallclause = "Folded",
    confluenceproblem = "AgdaConfluenceProblem",
}

local function handle_hl(msg)
    -- Highlight the text from `s` to `e` (exclusive), which is the range
    -- `key`, with `groups`.  During a load Agda sends the same ranges
    -- several times, so we replace the earlier highlighting of exactly
    -- the same range rather than adding to it.  Every group gets its own
    -- extmark, so that their attributes combine (e.g. the colour of a
    -- name and the underline of a coverage problem); earlier groups get
    -- a higher priority, as Agda sends the other aspects (errors and
    -- problems) before the kind of name.
    --
    -- Names (`v` with a definition site) are remembered in `hl_names`
    -- with the first extmark, which is added without a group if there is
    -- none.
    local function set_hl(key, s, e, groups, v)
        for _, id in ipairs(hl_marks[key] or {}) do
            vim.api.nvim_buf_del_extmark(main_buf, hl_ns, id)
            hl_names[id] = nil
        end
        local ids = {}
        for i = 1, math.max(#groups, v and 1 or 0) do
            ids[i] = vim.api.nvim_buf_set_extmark(main_buf, hl_ns, s[1], s[2], {
                end_row = e[1],
                end_col = e[2],
                hl_group = groups[i],
                priority = vim.hl.priorities.user + #groups - i,
            })
        end
        hl_marks[key] = ids
        if v then
            hl_names[ids[1]] = {v.definitionSite.filepath, v.definitionSite.position,
                                vim.tbl_contains(v.atoms, "operator")}
            hl_name_at[v.range[1]] = ids[1]
        end
    end

    -- `info` is missing if Agda wrote the highlighting to a file
    -- ("direct": false), which it does not do when we ask for Direct.
    if msg.info then
    for _, v in pairs(msg.info.payload) do
        local r = v.range
        local s = offset_pos(r[1])
        local e = offset_pos(r[2])
        local groups = {}
        for _, atom in ipairs(v.atoms) do
            table.insert(groups, hl_groups[atom])
        end

        if s == nil or e == nil then
            -- Only if the file that Agda loaded differs from the buffer.
            dprint("handle_hl: range outside the buffer " .. vim.inspect(v))
        else
            -- Agda sends `"definitionSite": null` for ranges that are not
            -- names.
            local name = v.definitionSite ~= nil and v.definitionSite ~= vim.NIL
            -- Updates without groups (e.g. only `typechecks`) keep the
            -- earlier highlighting.
            if #groups > 0 or name then
                set_hl(r[1] .. "-" .. r[2], s, e, groups, name and v)
            end
        end
    end
    end
end


-- Copy `text` to the system clipboard, so that it can be pasted into
-- other programs, or to the unnamed register if Neovim has no clipboard
-- provider.  Returns where it went, for the header of the popup.
local function copy(text)
    if vim.fn.has("clipboard") == 1 then
        vim.fn.setreg("+", text)
        return "copied to the clipboard"
    end
    vim.fn.setreg('"', text)
    return "copied to the \" register"
end

local function handle_displayinfo(msg)
    -- Adds the header and delimiter(s) to the list of lines.
    -- If `lines` is a singleton, and `sep` is not nil,
    -- we prepend `header` to the line, and only the top delimiter:
    --      ------------------------
    --      `header` `sep` `line[1]`
    --
    -- Otherwise, we add two delimiters around `header` like this:
    --      ------------------------
    --      `header`
    --      ------------------------
    --      `lines`
    --
    local function add_sep(lines,header,sep)
        -- Single-line output.
        if #lines == 1 and sep ~= nil then
            lines[1] = header .. sep .. lines[1]
            table.insert(lines, 1, SEP)
            return lines
        end

        -- Multiline ouput with header.
        table.insert(lines,1,header)
        table.insert(lines,2,SEP)
        table.insert(lines,1,SEP)
        return lines
    end

    local function mk_decl(name,lines,sep)
        local p = {}
        local spc = string.rep(" ", width(sep))
        for k,v in ipairs(lines) do
            if k == 1 then
                table.insert(p, name .. sep .. v)
                name = string.rep(" ", width(name))
            else
                table.insert(p, name .. spc .. v)
            end
        end
        return p
    end

    local function table_append(p,q)
        for _,v in ipairs(q) do
            table.insert(p,v)
        end
    end

    -- The lines of a context.  Like the Emacs mode, we show the names
    -- as Agda prints them in types (`reifiedName`, e.g. x₁ for a shadowed
    -- x) and mark those that are not in scope.  (Emacs also shows
    -- "x = x₁" if the original name is in scope, but the json does not
    -- say whether it is.)
    local function context_lines(entries)
        local p = {}
        local max_name_len = max_width(entries, "reifiedName")
        for _,v in ipairs(entries) do
            local name = v.reifiedName
            name = name .. string.rep(" ", max_name_len - width(name))
            local decl = mk_decl(name, split_lines(v.binding), " : ")
            if v.inScope == false then
                decl[#decl] = decl[#decl] .. "  (not in scope)"
            end
            table_append(p, decl)
        end
        return p
    end

    local inf = msg.info
    --dprint(inf)
    if (inf.kind == "Error") then
        -- Latest versions of Agda changed the interface.
        local text = inf.message or inf["error"].message
        -- If a goal command is waiting for a reload, the reload failed.
        -- Agda sends no interaction points then, so drop the command.
        -- Otherwise, if the prompt window is open, the error message (most
        -- likely!) is coming from the incorrect info we passed.  It should
        -- not indicate that the entire file needs loading.
        if sfunc ~= nil or pwin == nil then
            error_count = error_count + 1
            sfunc = nil
            sargs = nil
        end
        show_error(text)
        -- The warnings found before the error (e.g. termination problems),
        -- which Agda sends only here when a load fails.
        local ws = inf.warnings
        if type(ws) == "table" then
            ws = table.concat(vim.tbl_map(function (w) return w.message end, ws), "\n")
        end
        if type(ws) == "string" and ws ~= "" then
            display("Warnings\n    " .. ws:gsub("\n", "\n    "))
        end
    elseif inf.kind == "Context" then
        mk_window(add_sep(context_lines(inf.context), "Context"))
    elseif inf.kind == "InferredType" then
        mk_window(add_sep(split_lines(inf.expr), "Inferred Type", " : "))
    elseif inf.kind == "NormalForm" then
        local where = copy(inf.expr)
        mk_window(add_sep(split_lines(inf.expr), "Normal Form (" .. where .. ")", " : "))
    elseif inf.kind == "Auto" then
        display(string.format("Auto: %s", inf.info))
    elseif inf.kind == "ModuleContents" then
        -- The submodules (`names`), then the other names with their
        -- types.  The types go on the lines after the names, as long names
        -- would push aligned types far to the right.  Like the Emacs mode
        -- we do not show the `telescope`, which Agda uses as the context
        -- of the types.
        local indent = "  "
        local p = {"Modules"}
        for _,v in ipairs(inf.names) do
            table.insert(p, indent .. v)
        end
        table.insert(p, "Names")
        for _,v in ipairs(inf.contents) do
            table.insert(p, indent .. v.name)
            table_append(p, mk_decl(indent .. indent, split_lines(v.term), " : "))
        end
        mk_window(add_sep(p, "Module Contents"))
    elseif inf.kind == "WhyInScope" then
        mk_window(add_sep(split_lines(inf.message),
                      "Why `" .. inf.thing .. "' is in scope"
                      .. (why_scope and (" " .. why_scope) or "")))
    elseif inf.kind == "AllGoalsWarnings" then
        local m = {}
        local indent = "    "
        -- At some point the json API changed, and erros are put into the table instead of string.
        if type(inf.errors) == "string" and inf.errors ~= "" then
                table.insert(m, "Errors")
                for _,v in ipairs(vim.split(inf.errors, "\n")) do
                    table.insert(m, indent .. v)
                end
        end
        if type(inf.errors) == "table" and #inf.errors > 0 then
            table.insert(m, "Errors")
            for _,v in ipairs(inf.errors) do
                for k,w in ipairs(vim.split(v.message, "\n")) do
                    table.insert(m, string.format("%s%s", indent, w))
                end
            end
        end

        -- Same as above, in 2.6.2 json API changed.
        if type(inf.warnings) == "string" and inf.warnings ~= "" then
            table.insert(m, "Warnings")
            for _,v in ipairs(vim.split(inf.warnings, "\n")) do
                table.insert(m, indent .. v)
            end
        end
        if type(inf.warnings) == "table" and #inf.warnings > 0 then
            table.insert(m, "Warnings")
            for _,v in ipairs(inf.warnings) do
                for k,w in ipairs(vim.split(v.message, "\n")) do
                    table.insert(m, string.format("%s%s", indent, w))
                end
            end
        end

        if #inf.visibleGoals > 0 then
            table.insert(m, "Visible Goals")
            for _,v in ipairs(inf.visibleGoals) do
                table.insert(m, indent .. constraint.show(v))
            end
        end
        if #inf.invisibleGoals > 0 then
            table.insert(m, "Invisible Goals")
            for _,v in ipairs(inf.invisibleGoals) do
                table.insert(m, indent .. constraint.show_at(v, v.constraintObj.range))
            end
        end
        display(#m > 0 and table.concat(m, "\n") or "No goals, warnings or errors")
    elseif inf.kind == "Constraints" then
        if #inf.constraints == 0 then
            return display("No constraints")
        end
        local m = {"Constraints"}
        for _,c in ipairs(inf.constraints) do
            local text = constraint.show_at(c.constraint, c.range)
            for _,l in ipairs(split_lines(text)) do
                table.insert(m, "    " .. l)
            end
        end
        display(table.concat(m, "\n"))
    elseif inf.kind == "SearchAbout" then
        if #inf.results == 0 then
            return display("No definitions about " .. inf.search)
        end
        -- Like module contents, with the types below the names.
        local p = {}
        for _,v in ipairs(inf.results) do
            table.insert(p, v.name)
            table_append(p, mk_decl("  ", split_lines(v.term), " : "))
        end
        mk_window(add_sep(p, "Definitions about " .. inf.search))
    elseif inf.kind == "Version" then
        display("Agda version " .. inf.version)
    elseif inf.kind == "IntroNotFound" then
        display("No introduction forms found.")
    elseif inf.kind == "IntroConstructorUnknown" then
        -- As the Emacs mode: "a, b or c".
        local cs = inf.constructors
        local text = #cs < 2 and table.concat(cs)
            or table.concat(cs, ", ", 1, #cs - 1) .. " or " .. cs[#cs]
        display("Don't know which constructor to introduce of " .. text)
    elseif inf.kind == "GoalSpecific" then
        local p = {}
        local g = inf.goalInfo
        local ip = inf.interactionPoint
        if g.kind == "InferredType" then
            p = add_sep(split_lines(g.expr), "Inferred Type", " : ")
        elseif g.kind == "NormalForm" then
            local where = copy(g.expr)
            p = add_sep(split_lines(g.expr), "Normal Form (" .. where .. ")", " : ")
        elseif g.kind == "GoalType" then
            -- The goal type and the type of the goal's content, then
            -- the boundary (in Cubical Agda), the context and the
            -- constraints on the goal.
            p = mk_decl("Goal Type", split_lines(g.type), " : ")
            table.insert(p, 1, SEP)
            if g.typeAux.kind == "GoalAndHave" then
                table_append(p, mk_decl("Have Type", split_lines(g.typeAux.expr), " : "))
            end
            table.insert(p, SEP)
            if #g.boundary > 0 then
                table.insert(p, "Boundary:")
                for _,v in ipairs(g.boundary) do
                    table_append(p, split_lines(v))
                end
                table.insert(p, SEP)
            end
            table_append(p, context_lines(g.entries))
            -- The constraints that mention the goal, as Agda prints them.
            if g.outputForms and #g.outputForms > 0 then
                table.insert(p, SEP)
                table.insert(p, "Constraints:")
                for _,v in ipairs(g.outputForms) do
                    table_append(p, split_lines(v))
                end
            end
        elseif g.kind == "HelperFunction" then
            local where = copy(g.signature)
            p = add_sep(split_lines(g.signature), "Helper Function (" .. where .. ")")
        else
            for _,v in pairs(vim.split(vim.inspect(g), "\n")) do
                table.insert(p, v)
            end
            p = add_sep(p, "Don't know how to show " .. g.kind)
        end
        -- We assume that GoalSpecific things always have a location
        mk_window(p, Loc:new(ip.range[1].start.line, ip.range[1].start.col))
    else
        -- Agda sends information only in answer to a command, so say
        -- that we cannot show it rather than ignoring it.
        warning("cannot show Agda's " .. inf.kind .. " information:\n" .. vim.inspect(inf))
    end
end


-- Goals

-- This function runs continuations that might have been set by
-- goal commands in case the buffer was modified.
local function handle_interpoints(msg)
    goals = {}
    for _,v in pairs(msg.interactionPoints) do
        -- Interaction points can come without a range.
        if #v.range > 0 then
            local s = v.range[1].start
            local e = v.range[1]["end"]
            goals[v.id] = {
                ["start"] = Loc:new(s.line, s.col),
                ["end"]   = Loc:new(e.line, e.col)
            }
        end
    end
    --print("hanle interpoints, got: " .. len(goals) .. " goals")
    if sfunc ~= nil then
        -- Reset sfunc and sargs before running the continuation, so that
        -- they are reset even if it fails.
        local f, args = sfunc, sargs
        sfunc = nil
        sargs = nil
        f(unpack(args))
    end
end

-- Search `goals` for the goal at:
--   * loc                                   => in case it is set
--   * at the current location of the cursor => otherwise
local function get_current_goal(loc)
    loc = loc or get_current_loc() --Loc:new(vim.fn.line("."), vim.fn.virtcol("."))
    for k,v in pairs(goals) do
        if loc >= v.start and loc < v["end"] then
           return {k,v}
        end
    end
    return nil
end

-- The argument is a goal id.
local function get_goal_content(id)
    local n = goals[id]
    if n == nil then return nil end

    --dprint(n)
    local sl = n.start.line
    local sc = n.start.col
    local el = n["end"].line
    local ec = n["end"].col

    local content = vim.api.nvim_buf_get_lines(main_buf, sl-1, el, true)

    -- If the goal is "?", then it has no content.
    --print("get_goal_content: " .. content[1] .. ", " ..utf8.sub(content[1], sc, sc))
    if utf8.sub(content[1], sc, sc) == "?" then
        return ""
    end

    -- Now we assume that the goal is "{! ... !}".
    local l = #content
    --print("goal lines " .. l)
    if l == 1 then
        content[1] = utf8.sub(content[1], sc+2, ec-3)
    else
        content[1] = utf8.sub(content[1], sc+2)
        content[l] = utf8.sub(content[l], 1, ec-3)
    end
    return table.concat(content, "\n")
end

-- Close the prompt window and forget its content, which was sent to
-- Agda with the command that we got the response for.
local function reset_prompt()
    if pwin ~= nil then
        M.close_prompt_win()
        vim.api.nvim_buf_set_lines(pbuf, 0, -1, true, {})
    end
end

-- After the text from `s` to `e` (Locs) was replaced by `lines`, move the
-- goals behind it, so that later edits in the same response (e.g. auto
-- solving several goals on one line) find them.
local function shift_goals(s, e, lines)
    local dl = #lines - 1 - (e.line - s.line)
    -- The column where the text that followed `e` starts now.
    local col = (#lines == 1 and s.col or 1) + utf8.len(lines[#lines])
    local function shift(p)
        if p.line == e.line and p.col >= e.col then
            return Loc:new(p.line + dl, p.col - e.col + col)
        elseif p.line > e.line then
            return Loc:new(p.line + dl, p.col)
        end
        return p
    end
    for _, g in pairs(goals) do
        g.start = shift(g.start)
        g["end"] = shift(g["end"])
    end
end

-- Replace goal `id` in the main buffer by `text`.  Agda prints
-- multi-line text without indentation, so we indent the continuation
-- lines to the column of the goal.  We edit the buffer directly rather
-- than through a window: the response may arrive while the user is in
-- another window, and normal-mode commands are subject to mappings.
local function replace_goal(id, text)
    local n = goals[id]
    if n == nil then
        return warning(string.format("goal %s is not in the list of goals, reload the file", tostring(id)))
    end
    local s, e = n.start, n["end"]
    local first = vim.api.nvim_buf_get_lines(main_buf, s.line-1, s.line, true)[1]
    local last = vim.api.nvim_buf_get_lines(main_buf, e.line-1, e.line, true)[1]
    local sb = utf8.offset(first, s.col) - 1
    local eb = utf8.offset(last, e.col) - 1

    local lines = split_lines(text)
    local indent = string.rep(" ", width(first:sub(1, sb)))
    for i = 2, #lines do
        lines[i] = indent .. lines[i]
    end
    vim.api.nvim_buf_set_text(main_buf, s.line-1, sb, e.line-1, eb, lines)
    goals[id] = nil
    shift_goals(s, e, lines)

    -- 1-based lines, 0-based columns!
    if vim.api.nvim_get_current_buf() == main_buf then
        vim.api.nvim_win_set_cursor(0, {s.line, sb})
    end
end

local function handle_solve(soln)
    reset_prompt()
    replace_goal(soln.interactionPoint, "(" .. soln.expression .. ")")
end

local function handle_give(msg)
    reset_prompt()
    -- We always send noRange, so Agda never uses our text literally and
    -- `giveResult` is always {str = ...}, never {paren = ...}.
    replace_goal(msg.interactionPoint.id, msg.giveResult.str)
end

-- The byte column in `line` where the clause of an extended lambda
-- that contains the goal at byte column `sb` starts: right after the
-- `;` or the unmatched `{` before the goal, or `indent` (the end of the
-- indentation) if there is neither, as in a `λ where`.
local function extlam_clause_start(line, sb, indent)
    local depth = 0
    local i = sb
    while i > indent do
        local c = line:sub(i, i)
        if c == ";" or (c == "{" and depth == 0) then
            break
        elseif c == "{" then
            depth = depth - 1
        elseif c == "}" then
            depth = depth + 1
        end
        i = i - 1
    end
    return i
end

-- Replace the clause containing the goal with the clauses from a case
-- split.  Agda sends the clauses without indentation and does not say
-- which text they replace (see doc/make-case.md for a proper fix), so
-- like the Emacs mode we assume that the clause is on the lines of the
-- goal:
--   * a function clause starts on the line where the goal starts and
--     ends on the line where the goal ends: we replace these lines by
--     the clauses, indented like the first one.  So a clause whose
--     left-hand side or right-hand side spans several lines is not
--     replaced properly, and text after the goal on its last line (such
--     as a `where`) is lost;
--   * the clause of an extended lambda starts after the `;` or the `{`
--     before the goal on its line, and ends with the goal: we replace it
--     by the clauses separated by `;`.  If there is neither, the clause
--     is the first thing on the line (a `λ where`): we replace it by the
--     clauses on separate lines, indented like the first one.
local function handle_make_case(msg)
    reset_prompt()
    local n = goals[msg.interactionPoint.id]
    if n == nil then
        return warning(string.format("goal %d is not in the list of goals, reload the file", msg.interactionPoint.id))
    end
    local s, e = n.start, n["end"]
    local first = vim.api.nvim_buf_get_lines(main_buf, s.line-1, s.line, true)[1]
    local indent = first:match("^%s*")
    local clauses = {}
    for i, c in ipairs(msg.clauses) do
        clauses[i] = indent .. c
    end
    if msg.variant == "ExtendedLambda" then
        local last = vim.api.nvim_buf_get_lines(main_buf, e.line-1, e.line, true)[1]
        local sb = utf8.offset(first, s.col) - 1
        local eb = utf8.offset(last, e.col) - 1
        local cb = extlam_clause_start(first, sb, #indent)
        local text
        if cb == #indent then
            text = clauses
            text[1] = msg.clauses[1]
        else
            text = {" " .. table.concat(msg.clauses, " ; ")}
        end
        vim.api.nvim_buf_set_text(main_buf, s.line-1, cb, e.line-1, eb, text)
    else
        vim.api.nvim_buf_set_lines(main_buf, s.line-1, e.line, true, clauses)
    end
    -- Agda sends the interaction points from before the split after
    -- this response, so we reload to get the new goals, like the Emacs
    -- mode does.
    M.agda_load(main_file)
end

-- Move the cursor to the error, like the Emacs mode.  Agda sends this
-- after the error, during the load, so the buffer is as it was loaded.
-- Errors in other files (such as imported modules) are only reported.
local function handle_jump_to_error(msg)
    local win = main_window()
    if win == nil or main_file == nil
       or vim.uv.fs_realpath(msg.filepath) ~= vim.uv.fs_realpath(main_file) then
        return
    end
    local pos = offset_pos(msg.position)
    if pos == nil then
        return dprint("handle_jump_to_error: position outside the file " .. vim.inspect(msg))
    end
    vim.api.nvim_win_call(win, function ()
        vim.cmd("normal! m'")
        vim.api.nvim_win_set_cursor(win, {pos[1]+1, pos[2]})
    end)
end

--
-- Do the actual work depending on the returned messagess
local function handle_msg(msg)
    --dprint(msg)
    if (msg["kind"] == "HighlightingInfo") then
        handle_hl(msg)
    elseif (msg["kind"] == "DisplayInfo") then
        handle_displayinfo(msg)
    elseif msg["kind"] == "InteractionPoints" then
        handle_interpoints(msg)
    elseif msg["kind"] == "GiveAction" then
        handle_give(msg)
    elseif msg["kind"] == "SolveAll" then
        for _,soln in ipairs(msg.solutions) do
          handle_solve(soln)
        end
    elseif msg.kind == "MakeCase" then
        handle_make_case(msg)
    elseif msg.kind == "Status" or msg.kind == "ClearRunningInfo" then
        -- Not shown.
    elseif msg.kind == "RunningInfo" then
        display(msg.message)
    elseif msg.kind == "JumpToError" then
        handle_jump_to_error(msg)
    elseif msg.kind == "ClearHighlighting" then
        vim.api.nvim_buf_clear_namespace(main_buf,hl_ns,0,-1)
        hl_marks = {}
        hl_names = {}
        hl_name_at = {}
    else
        dprint("Don't know how to handle " .. msg["kind"]
              .. " :: " .. vim.inspect(msg))
    end
end

-- Handle one line of Agda's output.
--
-- We rely on Agda printing every message as exactly one line.  JSON
-- itself allows newlines between tokens, so this is a property of Agda,
-- not of the format.  In Agda 2.8.0 (src/full/Agda/Interaction):
--   * JSONTop.hs: `jsonREPL = repl (liftIO . BS.putStrLn <=< jsonifyResponse)`
--     with `jsonifyResponse = pure . encode <=< encodeTCM`, where `encode`
--     is aeson's compact encoder: no whitespace between tokens and
--     newlines in strings escaped as \n.
--   * AgdaTop.hs (`repl`): before reading each command Agda prints the
--     prompt "JSON> " without a newline, so it ends up in front of the
--     next message (several of them if commands produce no output).
--     If a command cannot be parsed, it prints the error ("cannot read:
--     <command>" or "not consumed: <rest>") as a plain line, not json.
--     Commands are read with `getLine`, so these are single lines too.
--   * Debug messages (-v) are sent as RunningInfo messages through the
--     same callback.
local function handle_line(line)
    while prefix("JSON> ", line) do
        line = string.sub(line, 7)
    end
    if line == "" then
        return
    end
    local ok, msg = pcall(vim.json.decode, line)
    if not ok then
        -- Agda prints failures to parse commands (e.g. "cannot read:")
        -- to stdout rather than stderr.
        show_error("Agda interaction error: " .. line)
        return
    end
    local ok2, err = xpcall(handle_msg, debug.traceback, msg)
    if not ok2 then
        show_error("Failed to handle Agda message " .. tostring(msg.kind) .. ": " .. err)
    end
end

local function on_event(job_id, data, event)
    -- Ignore processes that we have stopped.
    if job_id ~= agda_job then
        return
    end
    if event == "stdout"  then
        -- `data` is the chunk split at newlines (:h channel-lines): the
        -- first element continues the incomplete line from the previous
        -- chunk, the last one is incomplete ("" if the chunk ended with a
        -- newline).  A line may be spread over any number of chunks; it
        -- accumulates in `evbuf` until its newline arrives, so
        -- `handle_line` only ever sees complete lines.
        data[1] = evbuf .. data[1]
        evbuf = table.remove(data)
        for _, line in ipairs(data) do
            handle_line(line)
        end
    elseif event == "stderr" then
        -- At the end of the stream we get {""}.
        local text = table.concat(data, "\n")
        if vim.trim(text) ~= "" then
            show_error("Agda interaction error: " .. text)
        end
    elseif event == "exit" then
        agda_job = nil
        evbuf = ""
        sfunc = nil
        sargs = nil
        -- The goals refer to the old process; force a reload before the
        -- next goal command.
        goals = {}
        error_count = error_count + 1
        show_error(string.format("Agda exited unexpectedly (exit code %d)", data))
    end
end

-- Determine the version of Agda, as the command interface changes
-- between versions.  Returns false if Agda cannot be run.
local function detect_version()
    local ok, res = pcall(function ()
        return vim.system({agda_bin, "--version"}, {text = true}):wait()
    end)
    if not ok or res.code ~= 0 then
        show_error("Cannot run `" .. agda_bin .. " --version`: "
              .. (ok and vim.trim(res.stderr or "") or tostring(res)))
        return false
    end
    local major, minor, patch = string.match(res.stdout, "Agda version (%d+)%.(%d+)%.(%d+)")
    if major == nil then
        show_error("Cannot parse Agda version `" .. vim.trim(res.stdout) .. "`")
    else
        agda_major = tonumber(major)
        agda_minor = tonumber(minor)
        agda_patch = tonumber(patch)
    end
    return true
end

-- Whether the version of Agda is at least major.minor.patch.
local function version_at_least(major, minor, patch)
    if agda_major ~= major then return agda_major > major end
    if agda_minor ~= minor then return agda_minor > minor end
    return agda_patch >= (patch or 0)
end

-- Start Agda unless it is running already.  Returns whether Agda is
-- running.
function M.agda_start()
    if agda_job ~= nil then
        return true
    end
    if not detect_version() then
        return false
    end

    local t = {agda_bin}
    for _,arg in ipairs(agda_args) do
        table.insert(t, arg)
    end
    table.insert(t, "--interaction-json")
    local ok, job = pcall(vim.fn.jobstart,
        t,
        {
            on_stderr = on_event,
            on_stdout = on_event,
            on_exit = on_event,
            stdout_buffered = false,
            stderr_buffered = false,
        })
    if not ok or job <= 0 then
        show_error("Cannot start Agda: " .. (ok and ("jobstart returned " .. job) or job))
        return false
    end
    agda_job = job
    evbuf = ""
    return true
end

-- Stop Agda if it is running.
function M.agda_stop()
    local job = agda_job
    if job ~= nil then
        -- Reset first, so that on_event ignores the exit.
        agda_job = nil
        evbuf = ""
        sfunc = nil
        sargs = nil
        vim.fn.chanclose(job, "stdin")
        vim.fn.jobstop(job)
    end
end

local function agda_feed (file, cmd)
    if not M.agda_start() then
        -- Drop the continuation waiting for the response.
        sfunc = nil
        sargs = nil
        return
    end
    local msg = "IOTCM " .. haskell.string(file) .. " Interactive Direct " .. cmd
    vim.fn.chansend(agda_job, {msg, ""})
end

function M.agda_load (file)
    -- If the file changed on disk, let Neovim reload the buffer (or ask
    -- whether to), so that Agda checks what the buffer shows; otherwise
    -- the positions of highlighting and goals would not match.  Reloading
    -- runs the ftplugin again, which stops the Agda of this instance of
    -- the module and replaces it, so the new instance loads the file.
    vim.cmd("checktime " .. main_buf)
    local current = vim.b[main_buf].AgdaMod
    if current ~= nil and current.instance ~= M.instance then
        if sfunc ~= nil then
            sfunc, sargs = nil, nil
            warning("the file changed on disk and was reloaded, repeat the command")
        end
        return current.agda_load(file)
    end
    error_count = 0
    main_file = file
    -- if the main buffer changed, save it before issuing agda (re)load.
    if main_buf_changed() == 1 then
        vim.api.nvim_buf_call(main_buf, function () vim.cmd('w') end)
    end
    -- Update the variable holding the content of the buffer
    main_content = vim.api.nvim_buf_get_lines(main_buf, 0, -1, true)

    -- Precompute offset positions for the beginning and end of
    -- each line.  This will be used in the highlighting procedures.
    main_lines = {}
    local total = 1
    for i = 1, #main_content do
        local len = utf8.len(main_content[i])
        main_lines[i] = {total, total+len}
        total = total + len + 1
    end


    -- Agda resets the options on every load, so we pass the ones the
    -- user chose.
    local opts = {}
    if vim.b[main_buf].agda_show_implicit then
        table.insert(opts, haskell.string("--show-implicit"))
    end
    if vim.b[main_buf].agda_show_irrelevant then
        table.insert(opts, haskell.string("--show-irrelevant"))
    end
    agda_feed(file, "(Cmd_load " .. haskell.string(file) .. " ["
                    .. table.concat(opts, ",") .. "])")
end

------ Goal-specific helper functions ------
--------------------------------------------

-- Wrap a function to run after the goals are updated.
local function wrap_goal_action(func, file)
    if main_buf_changed() == 1 or error_count > 0 then
        if sfunc ~= nil then
            warning("an operation on the goal in progress")
            return
        end
        --print("suspending agda_context till the update")
        sfunc = func
        sargs = {}
        M.agda_load(file)
    else
        func()
    end
end

local function id_or_current_goal(id,loc)
    if id == nil then
        local n = get_current_goal(loc)
        if n ~= nil then
            return n[1]
        end
        return nil
    end
    return id
end

-- Get the content of the goal from the prompt buffer, or from the
-- goal, in case the prompt is empty.
local function get_trimmed_content(id)
    local content = ""
    -- Try getting content from the prompt window, if it is open for this
    -- goal (after it is closed, its buffer keeps the text).
    if pwin ~= nil and vim.api.nvim_win_is_valid(pwin) and pgoal == id then
        content = table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, true), "\n")
        content = vim.trim(content)
    end

    -- If prompt window doesn't exist or is empty, try
    -- looking inside the goal.
    if content == "" then
        content = vim.trim(get_goal_content(id))
    end
    return content
end

function M.agda_context(file)
    wrap_goal_action(function ()
        local n = get_current_goal()
        if n ~= nil then
            -- The goal content shold not matter
            local cmd = "(Cmd_context HeadNormal " .. n[1] .. " noRange \"\")"
            agda_feed(file, cmd)
        else
            warning("cannot infer goal type, the cursor is not in the goal")
        end
    end, file)
end


-- Show the goals (and warnings and errors) as Agda lists them after a
-- load, like the Emacs mode.
function M.agda_show_goals(file)
    wrap_goal_action(function ()
        agda_feed(file, "(Cmd_metas Simplified)")
    end, file)
end

-- The start positions of the goals in the order of the file.
local function goal_starts()
    local starts = {}
    for _, v in pairs(goals) do
        table.insert(starts, v.start)
    end
    table.sort(starts)
    return starts
end

-- Move the cursor of the current window to `pos`.
local function goto_loc(pos)
    local content = vim.api.nvim_buf_get_lines(main_buf, pos.line-1, pos.line, true)
    local o = utf8.offset(content[1], pos.col)
    -- 1-based lines, 0-based columns!
    vim.api.nvim_win_set_cursor(0, {pos.line, o-1})
end

-- Go to the first goal after the cursor, or to the first goal in the
-- file if there is none.
function M.agda_goal_next(file)
    local starts = goal_starts()
    if #starts == 0 then
        display(string.format("no goals in %s", file))
        return
    end
    local loc = get_current_loc()
    local pos = starts[1]
    for _, p in ipairs(starts) do
        if p > loc then
            pos = p
            break
        end
    end
    goto_loc(pos)
end

-- Go to the last goal before the cursor, or to the last goal in the
-- file if there is none.
function M.agda_goal_prev(file)
    local starts = goal_starts()
    if #starts == 0 then
        display(string.format("no goals in %s", file))
        return
    end
    local loc = get_current_loc()
    local pos = starts[#starts]
    for i = #starts, 1, -1 do
        if starts[i] < loc then
            pos = starts[i]
            break
        end
    end
    goto_loc(pos)
end

function M.agda_type_context(file,prec,id)
    -- Get the location of the cursor at the time we called `agda_type_context`.
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            return warning("cannot obtain goal type and context, the cursor is not in the goal")
        end

        if prec == nil then
            prec = "Simplified"
        end

        local cmd = "(Cmd_goal_type_context " .. prec .. " " .. id .. " noRange \"\")"
        agda_feed(file, cmd)
    end, file)
end

function M.agda_type_context_infer(file,prec,id)
    -- Get the location of the cursor at the time we called `agda_type_context`.
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            return warning("cannot obtain goal type and context, the cursor is not in the goal")
        end

        if prec == nil then
            prec = "Simplified"
        end

        local content = get_trimmed_content(id)
        dprint("Goal content: " .. content)
        local g = haskell.string(content)

        local cmd = "(Cmd_goal_type_context_infer " .. prec .. " " .. id .. " noRange " .. g .. ")"
        agda_feed(file, cmd)
    end, file)
end


local function agda_infer_toplevel(file, e)
    local e = haskell.string(e)
    local cmd = "(Cmd_infer_toplevel Normalised " .. e .. ")"
    agda_feed(file, cmd)
end

function M.agda_infer(file,id)
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            -- In case we are not in the goal, or the content of the goal
            -- is empty, prompt the user for the expression.
            local g = vim.fn.input("Expression: ")
            return agda_infer_toplevel(file, g)
        end
        local content = get_trimmed_content(id)
        if content == "" then
            return warning("The goal is empty")
        end
        local g = haskell.string(content)
        local cmd = "(Cmd_infer Normalised " .. id .. " noRange " .. g .. ")"
        agda_feed(file, cmd)
    end, file)
end

function M.agda_make_case(file,id)
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            return warning("cannot make case, the cursor is not in the goal")
        end
        local content = get_trimmed_content(id)
        if content == "" then
            content = vim.fn.input("Variables to split on: ")
        end
        local g = haskell.string(content)
        local cmd = "(Cmd_make_case " .. id .. " noRange " .. g .. ")"
        agda_feed(file, cmd)
    end, file)
end


function M.agda_refine(file,id)
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            return warning("cannot refine, the cursor is not in the goal")
        end

        local content = get_trimmed_content(id)
        local g = haskell.string(content)
        local cmd = "(Cmd_refine_or_intro False " .. id .. " noRange " .. g .. ")"
        agda_feed(file, cmd)
    end, file)
end

-- Give the goal's content, elaborated and simplified, like the Emacs
-- mode's elaborate and give (without a prefix argument): Agda checks the
-- expression and fills the goal with the result, e.g. with `ff` for
-- `not tt`.
function M.agda_elaborate_give(file,id)
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            return warning("cannot elaborate and give, the cursor is not in the goal")
        end
        local content = get_trimmed_content(id)
        if content == "" then
            return warning("The goal is empty")
        end
        agda_feed(file, "(Cmd_elaborate_give Simplified " .. id .. " noRange "
                        .. haskell.string(content) .. ")")
    end, file)
end

-- TODO ensure that we can pass the argument to Cmd_compute.  Right now
-- we are just hard-coding DefaultCompute, but there are other values one
-- can pass:
--   * DefaultCompute
--   * IgnoreAbstract
--   * UseShowInstance
--   * HeadCompute
--
local function agda_compute_toplevel(file, e)
    local e = haskell.string(e)
    local cmd = "(Cmd_compute_toplevel DefaultCompute " .. e .. ")"
    agda_feed(file, cmd)
end

function M.agda_compute(file,id)
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            -- In case we are not in the goal, or the content of the goal
            -- is empty, prompt the user for the expression.
            local g = vim.fn.input("Expression: ")
            return agda_compute_toplevel(file, g)
        end
        local content = get_trimmed_content(id)
        if content == "" then
            return warning("The goal is empty")
        end
        local g = haskell.string(content)
        local cmd = "(Cmd_compute DefaultCompute " .. id .. " noRange " .. g .. ")"
        agda_feed(file, cmd)
    end, file)
end

function M.agda_helper_fun(file,id)
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            return warning("cannot create helper function, the cursor is not in the goal")
        end
        local content = get_trimmed_content(id)
        if content == "" then
            content = vim.fn.input("Expression: ")
        end
        local g = haskell.string(content)
        local cmd = "(Cmd_helper_function AsIs " .. id .. " noRange " .. g .. ")"
        agda_feed(file, cmd)
    end, file)
end


local function agda_auto_toplevel(file)
    local cmd = "(Cmd_autoAll)"
    -- Agda changed interface after 2.7.0
    if version_at_least(2, 7) then
      cmd = "(Cmd_autoAll AsIs)"
    end
    agda_feed(file, cmd)
end

local function agda_solve_toplevel(file)
    local cmd = "(Cmd_solveAll Simplified)"
    agda_feed(file, cmd)
end

function M.agda_auto(file,id)
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            return agda_auto_toplevel(file)
        end
        local content = get_trimmed_content(id)
        local g = haskell.string(content)
        local cmd = "(Cmd_autoOne " .. id .. " noRange " .. g .. ")"
        -- Agda changed interface after 2.7.0
        if version_at_least(2, 7) then
          cmd = "(Cmd_autoOne AsIs " .. id .. " noRange " .. g .. ")"
        end
        agda_feed(file, cmd)
    end, file)
end

function M.agda_solve(file,id)
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            return agda_solve_toplevel(file)
        end
        local content = get_trimmed_content(id)
        local g = haskell.string(content)
        local cmd = "(Cmd_solveOne Simplified " .. id .. " noRange " .. g .. ")"
        agda_feed(file, cmd)
    end, file)
end

-- Show the contents of a module, like the Emacs mode: in a goal, of the
-- module named by the goal's content in the scope of the goal (asking
-- for the name if it is empty); otherwise of a module that we ask for,
-- in the scope at the top level of the file.  An empty name stands for
-- the current module: inside a module, Agda cannot resolve the module's
-- own name ("Not in scope").
function M.agda_module_contents(file)
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local prompt = "Module name (empty for the current module): "
        local id = id_or_current_goal(nil, loc)
        local name = id and get_trimmed_content(id) or ""
        if name == "" then
            name = vim.fn.input(prompt)
        end
        local cmd = id and ("(Cmd_show_module_contents Simplified " .. id .. " noRange ")
                    or "(Cmd_show_module_contents_toplevel Simplified "
        agda_feed(file, cmd .. haskell.string(name) .. ")")
    end, file)
end

------ Names and definitions ------
-----------------------------------

-- The name under the cursor in the main buffer, from the names in
-- Agda's highlighting: {text, data, start, end} where `data` is the
-- entry in `hl_names` and start and end are {0-based line, byte
-- column}, or nil.
local function name_at_cursor()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row, col = cursor[1] - 1, cursor[2]
    local marks = vim.api.nvim_buf_get_extmarks(main_buf, hl_ns, {row, col}, {row, col},
                                                {details = true, overlap = true})
    for _, m in ipairs(marks) do
        local data = hl_names[m[1]]
        local erow, ecol = m[4].end_row, m[4].end_col
        if data and (erow > row or ecol > col) then
            local text = vim.api.nvim_buf_get_text(main_buf, m[2], m[3], erow, ecol, {})
            return {text = table.concat(text, "\n"), data = data,
                    start = {m[2], m[3]}, ["end"] = {erow, ecol}}
        end
    end
end

-- The lines of `file`: of its buffer if it is loaded, otherwise as on
-- disk.
local function file_lines(file)
    local buf = vim.fn.bufnr(file)
    if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
        return vim.api.nvim_buf_get_lines(buf, 0, -1, true)
    end
    local ok, lines = pcall(vim.fn.readfile, file)
    return ok and lines or nil
end

-- The position of a definition site (`filepath` and `position`) as
-- {1-based line, byte column}, or nil.  Agda counts the position in code points from the start of the
-- file.  In the main buffer we take the extmark of the name at the
-- definition, which moved with any edits since the load.
local function in_main_file(filepath)
    return main_file ~= nil and vim.uv.fs_realpath(filepath) == vim.uv.fs_realpath(main_file)
end

local function site_pos(filepath, position)
    if in_main_file(filepath) then
        local id = hl_name_at[position]
        local p = id and vim.api.nvim_buf_get_extmark_by_id(main_buf, hl_ns, id, {})
        if p and #p > 0 then
            return {p[1] + 1, p[2]}
        end
        p = offset_pos(position)
        return p and {p[1] + 1, p[2]}
    end
    local lines = file_lines(filepath)
    local offset = 1
    for i, l in ipairs(lines or {}) do
        local len = utf8.len(l)
        if position <= offset + len then
            return {i, utf8.offset(l, position - offset + 1) - 1}
        end
        offset = offset + len + 1
    end
end

-- 'tagfunc' (set by the ftplugin): CTRL-] and the like jump to the
-- definition of the name under the cursor, and CTRL-T jumps back, like
-- M-. and M-* in the Emacs mode.  Only the cursor counts ("c" in
-- `flags`), not the word that Vim passes in `pattern`, which does not
-- know Agda's names.  For :tag with a name, or if there is no name under
-- the cursor, we return v:null, so that Vim uses tags files.
function M.tagfunc(pattern, flags)
    if not flags:find("c", 1, true) then
        return vim.NIL
    end
    local name = name_at_cursor()
    local pos = name and site_pos(name.data[1], name.data[2])
    if pos == nil then
        return vim.NIL
    end
    return {{
        name = name.text,
        filename = name.data[1],
        cmd = string.format([[/\%%%dl\%%%dc/]], pos[1], pos[2] + 1),
    }}
end

-- Characters that cannot be part of a name, as in Agda's lexer.
local not_name = "%s%.;{}()@\""

-- The name under the cursor for why-in-scope, from Agda's highlighting
-- (see `name_at_cursor`), or nil.  A part of an operator, such as `∧` in
-- `x ∧ y` or `then` in `if b then x else y`, is not in scope by itself,
-- so we take the name at its definition (`_∧_`, `if_then_else_`), with
-- the qualifier of the part, if any.
--
-- Limitation: if the operator was renamed when it was imported, e.g.
-- with `renaming (_∧_ to _and_)`, the definition has the old name, so
-- for `and` we ask about `_∧_`, which may not be in scope under that
-- name, and Agda answers that it is not.  The new name could only be
-- rebuilt from the parts at the use site, whose shape we do not know.
local function scope_name()
    local name = name_at_cursor()
    if name == nil or not name.data[3] then
        return name and name.text
    end
    local qualifier, part = name.text:match("^(.*%.)([^.]*)$")
    if qualifier == nil then
        qualifier, part = "", name.text
    end
    if part:find("_", 1, true) then
        return name.text        -- the whole operator, e.g. _∧_
    end
    local filepath = name.data[1]
    local pos = site_pos(filepath, name.data[2])
    local line
    if pos and in_main_file(filepath) then
        line = vim.api.nvim_buf_get_lines(main_buf, pos[1] - 1, pos[1], true)[1]
    elseif pos then
        line = (file_lines(filepath) or {})[pos[1]]
    end
    local def = line and line:sub(pos[2] + 1):match("^[^" .. not_name .. "]+")
    return def and (qualifier .. def) or name.text
end

-- A guess at the name under the cursor when Agda's highlighting has
-- none (e.g. before the first load): the characters around the cursor
-- that can be part of a (qualified) name.
local function guess_name()
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2]
    local chars = "[^%s;{}()@\"]*"
    local before = line:sub(1, col):match(chars .. "$")
    local after = line:sub(col + 1):match("^" .. chars)
    return ((before .. after):gsub("^%.+", ""):gsub("%.+$", ""))
end

-- Explain why a name is in scope, like the Emacs mode: in a goal with
-- contents, the contents in the context of the goal; otherwise the name
-- under the cursor, or a name from the user.
--
-- Outside goals Agda answers in the scope at the top level of the file
-- (Cmd_why_in_scope_toplevel uses the inside scope of the top-level
-- module), so names opened in a nested module are not in scope there.
-- Agda has no command for the scope at a position; see
-- doc/agda-upstream.md.  The header of the answer says which scope it
-- is for.
function M.agda_why_inscope(file)
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(nil, loc)
        if id ~= nil then
            local content = get_trimmed_content(id)
            if content == "" then
                content = vim.fn.input("Name: ")
            end
            if content ~= "" then
                why_scope = "in goal ?" .. id
                agda_feed(file, "(Cmd_why_in_scope " .. id .. " noRange "
                                .. haskell.string(content) .. ")")
            end
            return
        end
        local name = scope_name() or vim.fn.input("Name: ", guess_name())
        if name ~= "" then
            why_scope = "at the top level"
            agda_feed(file, "(Cmd_why_in_scope_toplevel " .. haskell.string(name) .. ")")
        end
    end, file)
end

function M.agda_show_constraints(file)
    wrap_goal_action(function ()
        local cmd = "(Cmd_constraints )"
        agda_feed(file,cmd)
    end, file)
end

function M.edit_goal(file)
    wrap_goal_action(function ()
        local n = get_current_goal()
        if n ~= nil then
            mk_prompt_window(file, n)
        else
            warning("cannot edit goal, the cursor is not in the goal")
        end
    end, file)
end

-- Show or hide implicit (and irrelevant) arguments.  Agda forgets the
-- choice when it loads the file, so we remember it in a buffer variable
-- (which also survives a new instance of the module) and pass it with
-- every load.
function M.show_implicit(file)
    vim.b[main_buf].agda_show_implicit = true
    agda_feed(file, "(ShowImplicitArgs True)")
end

function M.hide_implicit(file)
    vim.b[main_buf].agda_show_implicit = false
    agda_feed(file, "(ShowImplicitArgs False)")
end

-- Search for definitions, like the Emacs mode's search about.  Agda
-- splits the input into words: a word in double quotes must be part of
-- the definition's name, any other word is a name that its type must
-- mention (`findMentions` in Agda's Interaction/SearchAbout.hs).  So it
-- is not a search by type: `ℕ → ℕ` fails, as `→` is not a name.  Agda
-- searches in the scope at the top level of the file.
function M.agda_search_about(file)
    wrap_goal_action(function ()
        local s = vim.fn.input('Search about (names, "name parts"): ')
        if s ~= "" then
            agda_feed(file, "(Cmd_search_about_toplevel Simplified " .. haskell.string(s) .. ")")
        end
    end, file)
end

-- Show the version of the running Agda, with the commit it was built
-- from if it knows it.
function M.agda_version(file)
    agda_feed(file, "Cmd_show_version")
end

function M.show_irrelevant(file)
    vim.b[main_buf].agda_show_irrelevant = true
    agda_feed(file, "(ShowIrrelevantArgs True)")
end

function M.hide_irrelevant(file)
    vim.b[main_buf].agda_show_irrelevant = false
    agda_feed(file, "(ShowIrrelevantArgs False)")
end

return M
