local utf8 = require('agda.utf8')
local Loc = require('agda.loc')
local haskell = require('agda.haskell')

local M = {}

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

local showImplicitArgs = false

-- The buffer of the Agda file.  There is one instance of this module
-- per buffer, created by the ftplugin.
local main_buf = vim.api.nvim_get_current_buf()

-- Content and line-offset structure for handling
-- highlighting.
local main_content = ""
local main_lines = {}

-- Prompt window and buffer
local pwin = nil
local pbuf = nil
local pmin_width = 25

-- Whether to print debug information
local debug_p = false

-- Highlighting namespace.
local hl_ns = vim.api.nvim_create_namespace("agda-hl-ns")
-- The extmarks in `hl_ns` by the range they highlight ("start-end"
-- offsets as sent by Agda).
local hl_marks = {}


------ Helper functions ------
------------------------------

local function error(msg)
    vim.api.nvim_err_writeln(msg)
end

local function warning(msg)
    print("Warning: " .. msg)
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

local function debug(x)
    if debug_p then
        print(vim.inspect(x))
    end
end

local function dprint(...)
    if debug_p then
        print(...)
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

local function mk_delim(w)
    local s = ""
    for _ = 1,w do
        s = s .. "─"
    end
    return s
end

local function split_lines(s)
    return vim.split(s, "\n")
    -- local ls = {}
    -- for l in string.gmatch(s, "[^\n]+") do
    --     table.insert(ls, l)
    -- end
    -- return ls
end

-- This one reiles on the presence of main_buf variable.
-- TODO we also need to consider the case when the file
--      has been changed externally.  Otherwise locations
--      and definitions wouldn't match-up.
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

    local max = max_width(lines)
    vim.api.nvim_buf_set_lines(msg_buf, 0, -1, true, lines)

    M.close_msg_win()

    local state = {
        width=math.max(max,msg_min_width),
        height=#lines,
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

    --FIXME figure out a good way to give a message window a better color.
    --vim.cmd('hi Active ctermbg=DarkYellow ctermfg=Black')
    --vim.api.nvim_win_set_option(msg_win, 'winhl', "Normal:Active")
end

function M.close_msg_win()
    if msg_win ~= nil and vim.api.nvim_win_is_valid(msg_win) then
        vim.api.nvim_win_close(msg_win, true)
    end
    msg_win = nil
end


local function handle_hl(msg)
    -- Convert a (1-based, code point) offset into the file into a
    -- {0-based line, byte column} position by binary search in the
    -- line offsets.
    local function find_line(offset, lines, content)
        local lo, hi = 1, #lines
        while lo <= hi do
            local i = math.floor((lo + hi) / 2)
            if offset < lines[i][1] then
                hi = i - 1
            elseif offset > lines[i][2] then
                lo = i + 1
            else
                return {i-1, utf8.offset(content[i], offset-lines[i][1]+1)-1}
            end
        end
    end

    -- Highlight the text from `s` to `e` (exclusive), which is the range
    -- `key`, with `group`.  During a load Agda sends the same ranges
    -- several times, so we replace the earlier highlighting of exactly
    -- the same range rather than adding another one.
    local function set_hl(key, s, e, group)
        hl_marks[key] = vim.api.nvim_buf_set_extmark(main_buf, hl_ns, s[1], s[2], {
            id = hl_marks[key],
            end_row = e[1],
            end_col = e[2],
            hl_group = group,
            priority = vim.hl.priorities.user,
        })
    end

    -- Convert the names of the agda hl groups into the
    -- Vim ones.  TODO replace with table.
    local function translate_hl_group(name)
        if     (name == "keyword")  then return "Keyword"
        elseif (name == "symbol")   then return "Normal"
        elseif (name == "datatype") then return "Type"
        -- XXX we can give a distinct color to primitive types if we want to
        elseif (name == "primitivetype") then return "Type"
        elseif (name == "function") then return "Operator"
        elseif (name == "bound") then return "Identifier"
        elseif (name == "inductiveconstructor") then return "Constant"
        elseif (name == "number") then return "Number"
        elseif (name == "comment") then return "Comment"
        elseif (name == "hole") then return "Todo"
        elseif (name == "unsolvedmeta") then return "Todo"
        elseif (name == "string") then return "String"
        elseif (name == "catchallclause") then return "Folded"
        -- XXX I am not sure what's the purpose of highlighting
        --     areas that have been typechecked with a different color...
        elseif (name == "typechecks") then return "Normal"
        elseif (name == "module") then return "Structure"
        elseif (name == "postulate") then return "PreProc"
        elseif (name == "primitive") then return "PreProc"
        elseif (name == "error") then return "Error"
        elseif (name == "terminationproblem") then return "NonTerminating"
        elseif (name == "missingdefinition") then return "NoDefinition"
        -- TODO add more!
        else
            --name = name or "nil, WEIRD!!!"
            --dprint("Don't know hl-group for " .. name)
            return "Normal"
        end
    end


    -- `info` is missing if Agda wrote the highlighting to a file
    -- ("direct": false), which it does not do when we ask for Direct.
    if msg.info then
    for _, v in pairs(msg.info.payload) do
        local r = v.range
        -- FIXME s sometimes can be nil... Why?
        local s = find_line(r[1], main_lines, main_content)
        local e = find_line(r[2], main_lines, main_content)

        if s == nil or e == nil then
            dprint("handle_hl: crazy s=nil state " .. vim.inspect(v))
        elseif #v.atoms > 0 then
            local g = translate_hl_group(v.atoms[1])
            if g ~= "Normal" then
                set_hl(r[1] .. "-" .. r[2], s, e, g)
            end
        end
    end
    end
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
        -- FIXME we also need to consider `max_width`, as we can only have the window
        -- as large as the buffer/window width.
        --
        -- Single-line output.
        if #lines == 1 and sep ~= nil then
            lines[1] = header .. sep .. lines[1]
            table.insert(lines, 1, mk_delim(math.max(msg_min_width, width(lines[1]))))
            return lines
        end

        -- Multiline ouput with header.
        local m = max_width(lines)
        local l = mk_delim(math.max(msg_min_width, m))
        table.insert(lines,1,header)
        table.insert(lines,2,l)
        table.insert(lines,1,l)
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

    local inf = msg.info
    --debug(inf)
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
        error(text)
    elseif inf.kind == "Context" then
        local p = {}
        local max_name_len = max_width(inf.context, "originalName")
        for _,v in ipairs(inf.context) do
            -- FIXME we want reifiedName here, as it may differ.
            local name = v.originalName
            name = name .. string.rep(" ", max_name_len - width(name))
            table_append(p, mk_decl(name, split_lines(v.binding), " : "))
        end
        mk_window(add_sep(p,"Context"))
    elseif inf.kind == "InferredType" then
        mk_window(add_sep(split_lines(inf.expr), "Inferred Type", " : "))
    elseif inf.kind == "NormalForm" then
        mk_window(add_sep(split_lines(inf.expr), "Normal Form", " : "))
    elseif inf.kind == "Auto" then
        print(string.format("Auto: %s", inf.info))
    elseif inf.kind == "ModuleContents" then
        local indent = "   "
        local p = {}
        for _,v in ipairs(inf.contents) do
            table.insert(p, indent .. v.name)
            table_append(p, mk_decl(indent .. indent, split_lines(v.term), " : "))
        end
        mk_window(add_sep(p, "Module Content"))
    elseif inf.kind == "WhyInScope" then
        mk_window(add_sep(split_lines(inf.message),
                      "Why `" .. inf.thing .. "' is in scope"))
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

        if #inf.invisibleGoals > 0 then
            table.insert(m, "Invisible Goals")
            for _,v in ipairs(inf.invisibleGoals) do
                local o = v.constraintObj
                if type(o) == "table" then o = o.name end
                if v.type ~= nil then
                    table.insert(m, string.format("%s%s %s %s", indent, o, v.kind, v.type))
                else
                    table.insert(m, string.format("%s%s %s", indent, o, v.kind))
                end
            end
        end
        if #inf.visibleGoals > 0 then
            table.insert(m, "Visible Goals")
            for _,v in ipairs(inf.visibleGoals) do
        local o = v.constraintObj
        if type(o) == "table" then o = o.id end
                table.insert(m, string.format("%s%s %s %s", indent, o, v.kind, v.type))
            end
        end
        print(table.concat(m, "\n"))
        -- This is a way to see all the info at the same time, but this
        -- gets too noisy when we are in the middle of development.
        --vim.api.nvim_echo({ { table.concat(m, "\n") } }, true, {})
    elseif inf.kind == "GoalSpecific" then
        local p = {}
        local g = inf.goalInfo
        local ip = inf.interactionPoint
        if g.kind == "InferredType" then
            p = add_sep(split_lines(g.expr), "Inferred Type", " : ")
        elseif g.kind == "NormalForm" then
            p = add_sep(split_lines(g.expr), "Normal Form", " : ")
        elseif g.kind == "GoalType" then
            -- FIXME(artem) This is a quick hack to display boundary
            -- when using cubical agda.  Adjust the overall width 
            -- considering boundaries as well as type/context info.
            local max_b_len = 0
            if #g["boundary"] > 0 then
                table_append(p, { "Boundary: " })
                for _,v in pairs(g.boundary) do
                    local vs = split_lines(v)
                    max_b_len = math.max(max_b_len, max_width(vs))
                    table_append(p, vs)
                end
                table_append(p, { mk_delim(max_b_len) })
            end
            local max_name_len = max_width(g.entries, "reifiedName")

            for _,v in ipairs(g.entries) do
                local name = v.reifiedName
                name = name .. string.rep(" ", max_name_len - width(name))
                table_append(p, mk_decl(name, split_lines(v.binding), " : "))
            end
            local ty = split_lines(g.type)
            local gt = "Goal Type : "
            local ht = "Have Type : "

            -- If there is inferred type we want to show this as well
            local have_ty = {}
            if g.typeAux.kind == "GoalAndHave" then
                have_ty = split_lines(g.typeAux.expr)
            end

            -- XXX we can lift this into the add_sep, if this is a common case.
            for k,_ in ipairs(ty) do
                if k == 1 then
                    ty[k] = gt .. ty[k]
                else
                    ty[k] = string.rep(" ", width(gt)) .. ty[k]
                end
            end
            -- In case we have inferred type
            for k,_ in ipairs(have_ty) do
                if k == 1 then
                    have_ty[k] = ht .. have_ty[k]
                else
                    have_ty[k] = string.rep(" ", width(ht)) .. have_ty[k]
                end
            end

            local m = max_width(p)
            m = math.max(max_width(ty),m)
            m = math.max(max_width(have_ty),m)
            m = math.max(msg_min_width, m)
            local l = mk_delim(m)
            -- Insert line at the top of context
            table.insert(p,1,l)
            -- Insert line at the top of goal type
            table.insert(ty,1,l)
            -- Add inferred type to goal type (no delimiter)
            for _,v in ipairs(have_ty) do
                table.insert(ty,v)
            end
            -- Add context to `ty`
            for _,v in ipairs(p) do
                table.insert(ty,v)
            end
            p = ty
            --end
        elseif g.kind == "HelperFunction" then
            p = add_sep(split_lines(g.signature),
                        "Helper Function (copied to the \" register)")
            vim.fn.setreg('"', g.signature)
        else
            for _,v in pairs(vim.split(vim.inspect(g), "\n")) do
                table.insert(p, v)
            end
            p = add_sep(p, "Don't know how to show " .. g.kind)
        end
        -- We assume that GoalSpecific things always have a location
        mk_window(p, Loc:new(ip.range[1].start.line, ip.range[1].start.col))
    else
        dprint("Don't know how to handle DisplayInfo of kind: "
               .. inf.kind .. " :: " .. vim.inspect(msg))
    end
end


-- Goals
local function print_goals()
    for k,v in pairs(goals) do
        print (k .. " : " .. vim.inspect(v.start) .. vim.inspect(v["end"]))
    end
end

-- This function runs continuations that might have been set by
-- goal commands in case the buffer was modified.
local function handle_interpoints(msg)
    goals = {}
    for _,v in pairs(msg.interactionPoints) do
        -- FIXME sometimes there is no range in the output... wtf...
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

    --debug(n)
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

-- XXX deprecated function.
function M.gc()
    local n = get_current_goal()
    if n ~= nil then
      print("'" .. get_goal_content(n[1]) .. "'")
    else
      print("<empty-goal>")
    end
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

local function handle_make_case(msg)
    reset_prompt()
    local n = goals[msg.interactionPoint.id]
    if n == nil then
        return warning(string.format("goal %d is not in the list of goals, reload the file", msg.interactionPoint.id))
    end
    local sl = n.start.line --[1]
    local el = n["end"].line --[1]
    vim.api.nvim_buf_set_lines(main_buf, sl-1, el, true, msg.clauses)
end

local function handle_status(msg)
    local a = msg.status.showImplicitArgs
    if a ~= nil then
        showImplicitArgs = a
    end
end
--
-- Do the actual work depending on the returned messagess
local function handle_msg(msg)
    --debug(msg)
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
    elseif msg.kind == "Status" then
        handle_status(msg)
    elseif msg.kind == "RunningInfo" then
        print(msg.message)
    elseif msg.kind == "ClearHighlighting" then
        vim.api.nvim_buf_clear_namespace(main_buf,hl_ns,0,-1)
        hl_marks = {}
    else
        dprint("Don't know how to handle " .. msg["kind"]
              .. " :: " .. vim.inspect(msg))
    end
end

-- XXX deprecated function
function M.getevbuf()
    print("evbuf length is: " .. evbuf)
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
        error("Agda interaction error: " .. line)
        return
    end
    -- `debug` is shadowed by our own function.
    local ok2, err = xpcall(handle_msg, _G.debug.traceback, msg)
    if not ok2 then
        error("Failed to handle Agda message " .. tostring(msg.kind) .. ": " .. err)
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
            error("Agda interaction error: " .. text)
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
        error(string.format("Agda exited unexpectedly (exit code %d)", data))
    end
end

-- Determine the version of Agda, as the command interface changes
-- between versions.  Returns false if Agda cannot be run.
local function detect_version()
    local ok, res = pcall(function ()
        return vim.system({agda_bin, "--version"}, {text = true}):wait()
    end)
    if not ok or res.code ~= 0 then
        error("Cannot run `" .. agda_bin .. " --version`: "
              .. (ok and vim.trim(res.stderr or "") or tostring(res)))
        return false
    end
    local major, minor, patch = string.match(res.stdout, "Agda version (%d+)%.(%d+)%.(%d+)")
    if major == nil then
        error("Cannot parse Agda version `" .. vim.trim(res.stdout) .. "`")
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
        error("Cannot start Agda: " .. (ok and ("jobstart returned " .. job) or job))
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
    -- XXX should we kill evbuf in case we are stuck with an
    -- annoying error, or should it be done by a separate command?
    error_count = 0
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


    agda_feed(file, "(Cmd_load " .. haskell.string(file) .. " [])")
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
    -- Try getting content from the prompt window
    if pbuf ~= nil then
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


function M.agda_show_goals(file)
    local g = ""
    local c = 0
    for _,v in pairs(goals) do
        g = g .. string.format("#%02d    line %03d: ?\n", c, v.start.line)
        c = c + 1
    end
    if c > 0 then
        print(string.format("%d goal(s) in %s\n", c, file) .. g)
    else
        print(string.format("no goals in %s", file))
    end
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
        print(string.format("no goals in %s", file))
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
        print(string.format("no goals in %s", file))
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

-- XXX weird name of the function
local function toggle_implicit(file, b)
    if b then
        agda_feed(file, "(ShowImplicitArgs True)")
    else
        agda_feed(file, "(ShowImplicitArgs False)")
    end
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
        -- XXX not sure whether we can avoid this, it
        -- seems that agda_load sets the this flag to false.
        -- if not showImplicitArgs then
        --     toggle_implicit(file,true)
        --     agda_feed(file, cmd)
        --     toggle_implicit(file,false)
        -- else
        --     agda_feed(file, cmd)
        -- end
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
        debug("Goal content: " .. content)
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
        -- TODO handle IntroConstructorUnknown DisplayInfo
        --if content == "" then
        --    return warning("cannot refine empty goal")
        --end
        local g = haskell.string(content)
        local cmd = "(Cmd_refine_or_intro True " .. id .. " noRange " .. g .. ")"
        agda_feed(file, cmd)
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

-- TODO: show the contents of the current module.  Agda cannot resolve a
-- module's own name inside it ("Not in scope"), but an empty name gives
-- the current module (Agda 2.8.0), so the prompt should say that.  Also,
-- the ModuleContents handler only shows `contents`; it ignores `names`
-- (the submodules) and `telescope` (the module parameters), so a module
-- containing only submodules displays as empty.
function M.agda_module_contents(file)
    wrap_goal_action(function ()
        local content = vim.fn.input("Module Name: ")
        local e = haskell.string(content)
        local cmd = "(Cmd_show_module_contents_toplevel Simplified " .. e .. ")"
        agda_feed(file,cmd)
    end, file)
end

function M.agda_why_inscope(file)
    wrap_goal_action(function ()
        -- FIXME this is a bug when we have something like
        --       (F.blah + ...)
        --           ^
        --           |
        -- cWORD is returning `(F.blah`, what a nonsense...
        local content = vim.fn.expand("<cWORD>")
        local e = haskell.string(content)
        local cmd = "(Cmd_why_in_scope_toplevel " .. e .. ")"
        agda_feed(file,cmd)
    end, file)
end

-- TODO add show-constraints
-- NonInteractive Indirect ( Cmd_constraints ) function
-- Should be rather straight-forward

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

function M.show_implicit(file)
        agda_feed(file, "(ShowImplicitArgs True)")
end

function M.hide_implicit(file)
        agda_feed(file, "(ShowImplicitArgs False)")
end

return M
