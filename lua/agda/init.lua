local utf8 = require('lua-utf8')
local Loc = require('agda.loc')

local M = {}

------ State Variable ------
----------------------------

-- Agda Process Handle.  Created by `agda_start`.
local agda_bin = "agda"
local agda_job = nil

-- The list of goals in the format {id = {start = {l,c}, end = {l,c}}}
-- l and c are 1-based line and column as it is given by agda.
local goals = {}

-- Handles for the (vim)window and (vim)buffer that we use in
-- `mk_window` to display popups.
local msg_buf = nil
local msg_win = nil
local msg_min_width = 25

-- Buffer for the bytes coming from the agda process.
-- See `on_event` for the details on the usage.
local evbuf = ""

-- Variables to set continuation to be run by handle_interpoints
-- after updating the list of goals.
local sfunc = nil
local sargs = nil

local error_count = 0

local showImplicitArgs = false

-- Main window handles
-- XXX should we set them up at Agda load?
local main_win = vim.fn.win_getid()
local main_buf = vim.api.nvim_win_get_buf(main_win)

-- Prompt window and buffer
local pwin = nil
local pbuf = nil
local pmin_width = 25

-- Whether to print debug information
local debug_p = true

-- Highlighting namespace.
local hl_ns = vim.api.nvim_create_namespace("agda-hl-ns")


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
    l = 0
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

local function max_width(lines)
    local max = 0
    for k,v in pairs(lines) do
        local l = utf8.len(v)
        if l > max then
            max = l
        end
    end
    return max
end

local function mk_delim(w)
    local s = ""
    for i = 1,w do
        s = s .. "─"
    end
    return s
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

-- Get the first visible line number in the main window
local function main_win_visl()
    local w = vim.fn.win_getid()
    local visl = nil
    if w ~= main_win then
        vim.fn.win_gotoid(main_win)
        visl = vim.fn.line("w0")
        vim.fn.win_gotoid(w)
    else
        visl = vim.fn.line("w0")
    end
    return visl
end

local function get_current_loc()
    return Loc:new(vim.fn.line("."), vim.fn.virtcol("."))
end

------ Agda interaction-related functions ------
------------------------------------------------

function M.setup(config)
    if config and config.agda then
        agda_bin = config.agda
    end
end

function M.close_prompt_win()
    if pwin ~= nil then
        vim.api.nvim_win_close(pwin, true)
        pwin = nil
    end
end

-- goalid is a pair <id:int, loc:Loc>
local function mk_prompt_window(file, goal, loff)
    if pbuf == nil then
        pbuf = vim.api.nvim_create_buf(false, true)
        -- load unicode mappings.
        vim.api.nvim_buf_call(pbuf, function () vim.cmd("runtime agda-input.vim") end)
    end

    local status = {silent=true, nowait=true, noremap=true}
    local function mk_mapping(key, fun, args)
        vim.api.nvim_buf_set_keymap(
            pbuf, 'n', key, 
            ":lua require'agda'." .. fun .. "(" .. args .. ")<cr>",
            status)
    end
    mk_mapping("<LocalLeader>,", "agda_type_context", string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>d", "agda_infer",        string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>c", "agda_make_case",    string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>r", "agda_refine",       string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>n", "agda_compute",      string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>a", "agda_auto",         string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>h", "agda_helper_fun",   string.format("'%s', %d", file, goal[1]))
    mk_mapping("<LocalLeader>q", "close_msg_win",     "")
    mk_mapping("q",              "close_prompt_win",  "")

    local visl = loff or 1
    pwin = vim.api.nvim_open_win(
        pbuf, true,
        {
            relative='win',
            row=goal[2].start.line - visl + 1,
            col=goal[2].start.col,
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
    end

    local max = max_width(lines)
    vim.api.nvim_buf_set_lines(msg_buf, 0, -1, true, lines)

    if msg_win ~= nil then
        vim.api.nvim_win_close(msg_win, true)
    end

    state = {
        width=math.max(max,msg_min_width),
        height=#lines,
        style="minimal"
    }
    if loc == nil then
        state.relative='cursor'
        state.row=1
        state.col=1
    else
        local visl = main_win_visl()
        state.relative = 'win'
        state.row = loc.line - visl + 1
        state.col = loc.col
    end

    --print("mk_win: l="..(l or "nil")..", ".."c="..(c or "nil").."; "..vim.inspect(state))
    msg_win = vim.api.nvim_open_win(msg_buf, false, state)

    --FIXME figure out a good way to give a message window a better color.
    --vim.cmd('hi Active ctermbg=DarkYellow ctermfg=Black')
    --vim.api.nvim_win_set_option(msg_win, 'winhl', "Normal:Active")
end

function M.close_msg_win()
    if msg_win ~= nil then
        vim.api.nvim_win_close(msg_win, true)
        msg_win = nil
    end
end


local function handle_hl(msg)
    -- Get line lengths so that we can compute offsets
    -- in the (#line, #line-offset) format.
    local content = vim.api.nvim_buf_get_lines(main_buf, 0, -1, true)
    local lines = {}
    local total = 1
    for i = 1, #content do
        local len = utf8.len(content[i])
        lines[i] = {total, total+len}
        total = total + len + 1
    end

    -- Convert an offset into a line/lineoffset format
    -- that is suitable for the vim highlighter.
    -- XXX we can use binsearch here if we want to
    local function find_line(offset)
        for i,v in pairs(lines) do
            if (offset >= v[1] and offset <= v[2]) then
                return {i-1, utf8.offset(content[i], offset-v[1]+1)-1}
            end
        end
    end

    -- Convert the names of the agda hl groups into the
    -- Vim ones.  TODO replace with table.
    local function translate_hl_group(name)
        if     (name == "keyword")  then return "Keyword"
        elseif (name == "symbol")   then return "Normal"
        elseif (name == "datatype") then return "Type"
        elseif (name == "primitivetype") then return "Type"
        elseif (name == "function") then return "Operator"
        elseif (name == "bound") then return "Identifier"
        elseif (name == "inductiveconstructor") then return "Constant"
        elseif (name == "number") then return "Number"
        elseif (name == "comment") then return "Comment"
        elseif (name == "hole") then return "Todo"
        -- TODO add more!
        else
            --name = name or "nil, WEIRD!!!"
            --dprint("Don't know hl-group for " .. name)
            return "Normal"
        end
    end

    for k, v in pairs(msg.info.payload) do
        local r = v.range
        -- FIXME s sometimes can be nil... Why?
        local s = find_line(r[1])
        local e = find_line(r[2])

        if s == nil or e == nil then
            dprint("handle_hl: crazy s=nil state " .. vim.inspect(v))
        elseif #v.atoms > 0 then
            local g = translate_hl_group(v.atoms[1])
            -- We are using `highlight.range` instead of `nvim_buf_add_highlight`
            -- as we can have multiline comments.
            vim.highlight.range(main_buf,hl_ns,g,s,e)
        end
        --print("hl: [" .. vim.inspect(s) .. ", " .. vim.inspect(e) .. "]  ", v["atoms"][1])
    end
end


local function handle_displayinfo(msg)
    -- Add delimiting lines in the first position
    -- and in the third, in case the second argument is true.
    local function add_sep(lines,third_p)
        m = max_width(lines)
        l = mk_delim(math.max(msg_min_width, m))
        table.insert(lines,1,l)
        if third_p then
            table.insert(lines,3,l)
        end
        return lines
    end

    local inf = msg.info
    if (inf.kind == "Error") then
        -- Latest versions of Agda changed the interface.
        local text = inf.message or inf["error"].message
        -- if the prompt window is open, the error message (most likely!)
        -- is coming from the incorrect info we passed.  It should not
        -- indicate that the entire file needs loading.
        if pwin == nil then
            error_count = error_count + 1
            -- clear all the possible continuations
            sfunc = nil
            sargs = nil
        end
        vim.api.nvim_err_writeln(text)
    elseif inf.kind == "Context" then
        local p = {"Context"}
        for k,v in pairs(inf.context) do
            table.insert(p, v.originalName .. " : " .. v.binding)
        end
        mk_window(add_sep(p,true))
    elseif inf.kind == "InferredType" then
        mk_window(add_sep({"Inferred Type: " .. inf.expr}))
    elseif inf.kind == "NormalForm" then
        mk_window(add_sep({"Normal Form: " .. inf.expr}))
    elseif inf.kind == "GoalSpecific" then
        local p = {}
        local g = inf.goalInfo
        local ip = inf.interactionPoint
        if g.kind == "InferredType" then
            p = add_sep({"Inferred Type: " .. g.expr})
        elseif g.kind == "NormalForm" then
            p = add_sep({"Normal Form: " .. g.expr})
        elseif g.kind == "GoalType" then
            p = {"Goal Type: " .. g.type}
            for _,v in pairs(g.entries) do
                table.insert(p, v.originalName .. " : " .. v.binding)
            end
            p = add_sep(p,true)
        elseif g.kind == "HelperFunction" then
            p = {"Helper Function (copied to the \" register)",
                 g.signature}
            p = add_sep(p,true)
            vim.fn.setreg('"', g.signature)
        else
            p = {"Don't know how to show " .. g.kind}
            for _,v in pairs(vim.split(vim.inspect(g), "\n")) do
                table.insert(p, v)
            end
            p = add_sep(p,true)
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
    for k,v in pairs(msg.interactionPoints) do
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
        --print("resuming suspended function")
        -- Run continuation, reset sfunc and sargs.
        sfunc(unpack(sargs))
        sfunc = nil
        sargs = nil
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
    n = get_current_goal()
    print("'" .. get_goal_content(n[1]) .. "'")
end


local function handle_give(msg)
    --debug(msg)
    local n = goals[msg.interactionPoint.id]
    local sl = n.start.line
    local sc = n.start.col
    local el = n["end"].line
    local ec = n["end"].col

    -- Fucking vim api is in bytes!
    local content = vim.api.nvim_buf_get_lines(main_buf, sl-1, sl, true)
    local r = msg.giveResult.str
    local o = utf8.offset(content[1], sc)
    if pwin ~= nil then
        M.close_prompt_win()
        vim.api.nvim_buf_set_lines(pbuf, 0, -1, true, {})
    end
    -- 1-based lines, 0-based columns!
    vim.api.nvim_win_set_cursor(main_win, {sl, o-1})
    -- if the goal is "?"
    if utf8.sub(content[1], sc, sc) == "?" then
        vim.cmd("normal cl" .. r)
    else
        vim.cmd("normal ca{" .. r)
    end
end

local function handle_make_case(msg)
    local n = goals[msg.interactionPoint.id]
    local sl = n.start.line --[1]
    local el = n["end"].line --[1]
    vim.api.nvim_buf_set_lines(main_buf, sl-1, el, true, msg.clauses)

    if pwin ~= nil then
        --print("closing window, setting buffer to nothing")
        M.close_prompt_win()
        vim.api.nvim_buf_set_lines(pbuf, 0, -1, true, {})
    end
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
    elseif msg.kind == "MakeCase" then
        handle_make_case(msg)
    elseif msg.kind == "Status" then
        handle_status(msg)
    elseif msg.kind == "RunningInfo" then
        print(msg.message)
    elseif msg.kind == "ClearHighlighting" then
        vim.api.nvim_buf_clear_namespace(main_buf,hl_ns,0,-1)
    else 
        dprint("Don't know how to handle " .. msg["kind"]
              .. " :: " .. vim.inspect(msg))
    end
end

-- XXX deprecated function
function M.getevbuf()
    print("evbuf length is: " .. evbuf)
end

local function on_event(job_id, data, event)
    if event == "stdout"  then
        for _ , vv in pairs(data) do
            local v = utf8.gsub(vv, "^JSON> ", "")
            if v ~= "" then
                --print("on_event: " .. counter .. ", " 
                --      .. string.sub(v, 1, 100) .. " ... "
                --      .. string.sub(v, -100)
                --      .. " evbuf: '" .. string.sub(evbuf, 1, 5) .. "'")
                -- XXX We assume that this starts the new json message,
                -- therefore we can execute the previously accumulated buffer.
                if prefix("{\"kind\":", v) or prefix("{\"status\":", v) then
                    if evbuf ~= "" then
                        handle_msg (vim.fn.json_decode(evbuf))
                    end
                    evbuf = v
                else
                    evbuf = evbuf .. v
                end
            end
        end
        -- If we have a valid json message in the evbuf, let's
        -- execute it.  If not, we leave it for the next time this
        -- function is called.
        if evbuf ~= "" and pcall (vim.fn.json_decode, evbuf) then
            handle_msg (vim.fn.json_decode(evbuf))
            evbuf = ""
        else
            --print("Leaving evbuf for later")
        end
    elseif event == "stderr" then
        error("Agda interaction error: " .. table.concat(data, "\n"))
    end
end

-- TODO we need to define a function that terminates the process
-- and call it at exit.
function M.agda_start()
    agda_job = vim.fn.jobstart(
        {agda_bin, "--interaction-json"},
        {
            on_stderr = on_event,
            on_stdout = on_event,
            on_exit = on_event,
            stdout_buffered = false,
            stderr_buffered = false,
        })
end

local function agda_feed (file, cmd)
    if (agda_job == nil) then
        M.agda_start()
    end
    local msg = "IOTCM \"" .. file .. "\" Interactive Direct " .. cmd
    vim.fn.jobsend(agda_job, {msg, ""})
end

function M.agda_load (file)
    -- XXX should we kill evbuf in case we are stuck with an
    -- annoying error, or should it be done by a separate command?
    error_count = 0
    -- if the main buffer changed, save it before issuing agda (re)load.
    if main_buf_changed() == 1 then
        vim.api.nvim_buf_call(main_buf, function () vim.cmd('w') end)
    end
    agda_feed(file, "(Cmd_load \"" .. file .. "\" [])")
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
        n = get_current_goal(loc)
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
    if pbuf ~= nil then
        content = table.concat(vim.api.nvim_buf_get_lines(pbuf, 0, -1, true), "\n")
    else
        content = get_goal_content(id)
    end
    return vim.trim(content)
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
        g = g .. string.format("    line %03d: ?", v.start.line)
        c = c + 1
    end
    if c > 0 then
        print(string.format("%d goal(s) in %s\n", c, file) .. g)
    else
        print(string.format("no goals in %s", file))
    end
end

function M.agda_goal_next(file)
    local loc = get_current_loc()
    if len(goals) == 0 then
        print(string.format("no goals in %s", file))
    end
    local pos = nil
    for k,v in pairs(goals) do
        if v.start > loc then
            pos = v.start
        end
    end
    -- if we didn't find the goal after the cursor
    -- just return the first goal in the list
    if pos == nil then
        pos = goals[0].start
    end

    local content = vim.api.nvim_buf_get_lines(main_buf, pos.line-1, pos.line, true)
    local o = utf8.offset(content[1], pos.col)
    -- 1-based lines, 0-based columns!
    vim.api.nvim_win_set_cursor(main_win, {pos.line, o-1})
end


function M.agda_goal_prev(file)
    local loc = get_current_loc()
    if len(goals) == 0 then
        print(string.format("no goals in %s", file))
    end

    -- We have a 0-indexed table of goals which is not
    -- canonical in lua.  Therefore we have to take an extra
    -- step to traverse it in reverse.
    local ix = {}
    for k,_ in pairs(goals) do
        table.insert(ix,k)
    end
    -- Fuck you LUA, fucking piece of shit!
    -- As 0 is a non-canonical index, it is inserted at the end
    -- of the table.  What a nonsense!
    table.sort(ix)

    local pos = nil
    for i = #ix,1,-1 do
        if goals[ix[i]].start < loc then
            pos = goals[ix[i]].start
        end
    end
    -- if we didn't find the goal before the cursor,
    -- return the last goal in the list
    if pos == nil then
        pos = goals[ix[#ix]].start
    end

    local content = vim.api.nvim_buf_get_lines(main_buf, pos.line-1, pos.line, true)
    local o = utf8.offset(content[1], pos.col)
    -- 1-based lines, 0-based columns!
    vim.api.nvim_win_set_cursor(main_win, {pos.line, o-1})
end

-- XXX weird name of the function
local function toggle_implicit(file, b)
    if b then
        agda_feed(file, "(ShowImplicitArgs True)")
    else
        agda_feed(file, "(ShowImplicitArgs False)")
    end
end

function M.agda_type_context(file,id)
    -- Get the location of the cursor at the time we called `agda_type_context`.
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            return warning("cannot obtain goal type and context, the cursor is not in the goal")
        end

        local cmd = "(Cmd_goal_type_context Normalised " .. id .. " noRange \"\")"
        -- XXX not sure whether we can avoid this, it
        -- seems that agda_load sets the this flag to false.
        if not showImplicitArgs then
            toggle_implicit(file,true)
            agda_feed(file, cmd)
            toggle_implicit(file,false)
        else
            agda_feed(file, cmd)
        end
    end, file)
end

local function agda_infer_toplevel(file, e)
    local cmd = "(Cmd_infer_toplevel Normalised \"" .. e .. "\")"
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
        local g = vim.fn.json_encode(content) -- puts "" around, and escapes \n
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
        local g = vim.fn.json_encode(content)
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
        local g = vim.fn.json_encode(content)
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
    local cmd = "(Cmd_compute_toplevel DefaultCompute \"" .. e .. "\")"
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
        local g = vim.fn.json_encode(content) -- puts "" around, and escapes \n
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
        local g = vim.fn.json_encode(content) -- puts "" around, and escapes \n
        local cmd = "(Cmd_helper_function AsIs " .. id .. " noRange " .. g .. ")"
        agda_feed(file, cmd)
    end, file)
end


local function agda_auto_toplevel(file, e)
    local cmd = "(Cmd_autoAll)"
    agda_feed(file, cmd)
end

function M.agda_auto(file,id)
    local loc = get_current_loc()
    wrap_goal_action(function ()
        local id = id_or_current_goal(id, loc)
        if id == nil then
            return agda_auto_toplevel(file, g)
        end
        local content = get_trimmed_content(id)
        -- TODO Handle reply from Auto.
        local g = vim.fn.json_encode(content) -- puts "" around, and escapes \n
        local cmd = "(Cmd_autoOne " .. id .. " noRange " .. g .. ")"
        agda_feed(file, cmd)
    end, file)
end

function M.edit_goal(file)
    wrap_goal_action(function ()
        local n = get_current_goal()
        if n ~= nil then
            local visl = vim.fn.line("w0")
            mk_prompt_window(file, n, visl)
        else
            warning("cannot edit goal, the cursor is not in the goal")
        end
    end, file)
end

function M.toggle_implicit(file, b)
    if b then
        agda_feed(file, "(ShowImplicitArgs True)")
    else
        agda_feed(file, "(ShowImplicitArgs False)")
    end
end

return M
