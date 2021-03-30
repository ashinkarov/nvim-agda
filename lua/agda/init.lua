local utf8 = require('lua-utf8')

local M = {}

-- Agda Process Handle.  Created by `agda_start`.
local agda_job = nil

-- The list of goals in the format {id = {start = {l,c}, end = {l,c}}}
-- l and c are 1-based line and column as it is given by agda.
local goals = {}

-- Handles for the (vim)window and (vim)buffer that we use in
-- `mk_window` to display popups.
local msg_buf = nil
local msg_win = nil

-- Buffer for the bytes coming from the agda process.
-- See `on_event` for the details on the usage.
local evbuf = ""



-- Helper functions
local function error(msg)
    vim.api.nvim_err_writeln(msg)
end

local function warning(msg)
    print("Warning: " .. msg)
end

local function prefix(p, s)
    return p == string.sub(s, 1, #p)
end

-- Create window for messages
local function mk_window(lines)
    if msg_buf == nil then
        msg_buf = vim.api.nvim_create_buf(false, true)
    end

    local closingKeys = {'<Esc>', '<CR>', '<Leader>'}
    for _,k in pairs(closingKeys) do
        vim.api.nvim_buf_set_keymap(
            msg_buf, 'n', k, ':close<CR>',
            {silent=true, nowait=true, noremap=true})
    end

    local max = 0
    for k,v in pairs(lines) do
        l = utf8.len(v)
        lines[k] = " " .. lines[k]
        if l > max then
            max = l
        end
    end

    vim.api.nvim_buf_set_lines(msg_buf, 0, -1, true, lines)

    if msg_win ~= nil then
        vim.api.nvim_win_close(msg_win, true)
    end

    msg_win = vim.api.nvim_open_win(
        msg_buf, false,
        {
            relative='cursor',
            row=1,
            col=1,
            width=max+2,
            height=#lines+2,
            style="minimal"
        })

    --vim.api.nvim_win_set_option(msg_win, 'winhl', "Normal:ErrorFloat")
end

function M.close_msg_win()
    if msg_win ~= nil then
        vim.api.nvim_win_close(msg_win, true)
        msg_win = nil
    end
end


local function handle_hl(msg)
    local winnr = vim.fn.win_getid()
    local bufnr = vim.api.nvim_win_get_buf(winnr)

    -- Get line lengths so that we can compute offsets
    -- in the (#line, #line-offset) format.
    local content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, true)
    local lines = {}
    local total = 1
    for i = 1, #content do
        local len = utf8.len(content[i])
        lines[i] = {total, total+len}
        --print("line-"..i..": ".. content[i], vim.inspect(lines[i]))
        total = total + len + 1
    end

    -- Convert an offset into a line/lineoffset format
    -- taht is suitable for the vim highlighter.
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
        -- TODO add more!
        else
            --name = name or "nil, WEIRD!!!"
            --print("Don't know hl-group for " .. name)
            return "Normal"
        end
    end

    for k, v in pairs(msg.info.payload) do
        local r = v.range
        -- FIXME s sometimes can be nil... Why?
        local s = find_line(r[1])
        local e = find_line(r[2])
        if #v.atoms > 0 then
            local g = translate_hl_group(v.atoms[1])
            -- We are using the direct api call here instead of
            -- vim.highlight.range(bufnr, -1, g, s, e), as we are sure
            -- that the range that Agda sends is located on the same line.
            vim.api.nvim_buf_add_highlight(bufnr, -1, g, s[1], s[2], e[2])
        end
        --print("hl: [" .. vim.inspect(s) .. ", " .. vim.inspect(e) .. "]  ", v["atoms"][1])
    end
end


local function handle_displayinfo(msg)
    local delim_line = "================="
    local inf = msg.info

    if (inf.kind == "Error") then
        vim.api.nvim_err_write("Error: " .. inf.message)
    elseif inf.kind == "Context" then
        --print(vim.inspect(msg))
        local p = {"Context", deilim_line}
        for k,v in pairs(inf.context) do
            table.insert(p, v.originalName .. " : " .. v.binding)
        end
        mk_window(p)
    elseif inf.kind == "GoalSpecific" then
        local p = {}
        local g = inf.goalInfo
        if g.kind == "InferredType" then
            p = {"Inferred Type: " .. g.expr, delim_line}
        elseif g.kind == "GoalType" then
            p = {"Goal Type: " .. g.type, delim_line}
            for _,v in pairs(g.entries) do
                table.insert(p, v.originalName .. " : " .. v.binding)
            end
        else
            p = {"Don't know how to show " .. g.kind, delim_line}
            for _,v in pairs(vim.split(vim.inspect(g), "\n")) do
                table.insert(p, v)
            end
        end
        mk_window(p)
    else
        print("Don't know how to handle DisplayInfo of kind: " 
              .. inf.kind .. " :: " .. vim.inspect(msg))
    end
end


-- Goals
local function handle_interpoints(msg)
    for k,v in pairs(msg["interactionPoints"]) do
        local s = v["range"][1]["start"]
        local e = v["range"][1]["end"]
        goals[v["id"]] = {["start"] = {s["line"], s["col"]},
                          ["end"] = {e["line"], e["col"]}}
        --print("goal " .. v["id"] .. " :: " .. vim.inspect(goals[v["id"]]))
    end
end

local function get_current_goal()
    local l = vim.fn.line(".")
    local c = vim.fn.virtcol(".")
    --print("cur-loc: (" .. l .. ", " .. c ..")")
    local function cmp_lb(a, b)
        if a[1] <= b[1] then return true
        elseif a[1] == b[1] then return a[2] <= b[2] end
        return false
    end
    local function cmp_ub(a, b)
        if a[1] < b[1] then return true
        elseif a[1] == b[1] then return a[2] < b[2] end
        return false
    end
    for k,v in pairs(goals) do
        if cmp_lb(v.start, {l,c}) and cmp_ub({l,c}, v["end"]) then
           return {k,v}
        end
    end
    return nil
    --print(l, c)
end

-- The argument is a pair obtained from the get_current_goal.
local function get_goal_content(n)
    --local n = get_current_goal()
    if n == nil then return nil end

    local sl = n[2].start[1]
    local sc = n[2].start[2]
    local el = n[2]["end"][1]
    local ec = n[2]["end"][2]

    local winnr = vim.fn.win_getid()
    local bufnr = vim.api.nvim_win_get_buf(winnr)
    local content = vim.api.nvim_buf_get_lines(bufnr, sl-1, el, true)

    -- If the goal is "?", then it has no content.
    if utf8.sub(content[1], sc, sc+1) == "?" then
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

function M.gc()
    n = get_current_goal()
    print("'" .. get_goal_content(n) .. "'")
end

-- XXX This function works fine but it does not preserve hilighting
-- Replace the goal with the refined result
local function handle_give_XXX(msg)
    --print(vim.inspect(msg))
    local winnr = vim.fn.win_getid()
    local bufnr = vim.api.nvim_win_get_buf(winnr)

    local n = goals[msg.interactionPoint.id]
    local sl = n.start[1]
    local sc = n.start[2]
    local el = n["end"][1]
    local ec = n["end"][2]

    local content = vim.api.nvim_buf_get_lines(bufnr, sl-1, el, true)

    -- Now we assume that the goal is "{! ... !}".
    local l = #content
    local r = msg.giveResult.str
    --print("goal lines " .. l)
    local pref = utf8.sub(content[1], 1, sc-1) .. r
    local post = utf8.sub(content[l], ec)
    if l == 1 or post == "" then
        vim.api.nvim_buf_set_lines(bufnr, sl-1, el, true, {pref .. post})
    else
        vim.api.nvim_buf_set_lines(bufnr, sl-1, el, true, {pref, post})
    end
end


local function handle_give(msg)
    local winnr = vim.fn.win_getid()
    local bufnr = vim.api.nvim_win_get_buf(winnr)
    local n = goals[msg.interactionPoint.id]
    local sl = n.start[1]
    local sc = n.start[2]
    local el = n["end"][1]
    local ec = n["end"][2]

    -- Fucking vim apu is in bytes!
    local content = vim.api.nvim_buf_get_lines(bufnr, sl-1, sl, true)
    local r = msg.giveResult.str
    local o = utf8.offset(content[1], sc)
    -- 1-based lines, 0-based columns!
    vim.api.nvim_win_set_cursor(winnr, {sl, o-1})
    vim.cmd("normal ca{" .. r)
end

--
-- Do the actual work depending on the returned messagess
local function handle_msg(msg)
    if (msg["kind"] == "HighlightingInfo") then 
        handle_hl(msg)
    elseif (msg["kind"] == "DisplayInfo") then
        handle_displayinfo(msg)
    elseif msg["kind"] == "InteractionPoints" then
        handle_interpoints(msg)
    elseif msg["kind"] == "GiveAction" then
        handle_give(msg)
    else 
        print("Don't know how to handle " .. msg["kind"]
              .. " :: " .. vim.inspect(msg))
    end
end


function M.getevbuf()
    print("evbuf length is: " .. evbuf)
end

local function on_event(job_id, data, event)
    if event == "stdout" or event == "stderr" then
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
    end
end

function M.agda_start()
    agda_job = vim.fn.jobstart(
        {"agda", "--interaction-json"},
        {
            on_stderr = on_event,
            on_stdout = on_event,
            on_exit = on_event,
            stdout_buffered = false,
            stderr_buffered = false,
        })
    --print("agda job is: ".. agda_job)
end

local function agda_feed (file, cmd)
    if (agda_job == nil) then
        M.agda_start()
    end
    local msg = "IOTCM \"" .. file .. "\" NonInteractive Direct " .. cmd
    vim.fn.jobsend(agda_job, {msg, ""})
end

function M.agda_load (file)
    agda_feed(file, "(Cmd_load \"" .. file .. "\" [])")
end

function M.agda_context(file)
    local n = get_current_goal()
    if n ~= nil then
        -- The goal content shold not matter
        local cmd = "(Cmd_context Normalised " .. n[1] .. " noRange \"\")"
        agda_feed(file, cmd)
    else
        warning("cannot infer goal type, the cursor is not in the goal")
    end
end

function M.agda_type_context(file)
    local n = get_current_goal()
    if n ~= nil then
        -- The goal content shold not matter
        local cmd = "(Cmd_goal_type_context Normalised " .. n[1] .. " noRange \"\")"
        agda_feed(file, cmd)
    else
        warning("cannot infer goal type, the cursor is not in the goal")
    end
end

local function agda_infer_toplevel(file, e)
    local cmd = "(Cmd_infer_toplevel Normalised \"" .. e .. "\")"
    agda_feed(file, cmd)
end

function M.agda_infer(file)
    local n = get_current_goal()
    if n ~= nil then
        -- This encoding is crucial for the following reasons:
        -- 1. As the goal content may span over a few lines,
        --    each \n has to be quoted;
        -- 2. It puts "" around the string.
        local content = get_goal_content(n)
        if vim.trim(content) ~= "" then 
           local g = vim.fn.json_encode(content)
           local cmd = "(Cmd_infer Normalised " .. n[1] .. " noRange " .. g .. ")"
           agda_feed(file, cmd)
           return
        end
    end
    -- In case we are not in the goal, or the content of the goal
    -- is empty, prompt the user for the expression.
    local g = vim.fn.input("Expression: ")
    agda_infer_toplevel(file, g)
end

function M.agda_refine(file)
    local n = get_current_goal()
    if n ~= nil then
        local g = vim.fn.json_encode(get_goal_content(n))
        local cmd = "(Cmd_refine_or_intro True " .. n[1] .. " noRange " .. g .. ")"
        agda_feed(file, cmd)
    else
        warning("cannot refine, the cursor is not in the goal")
    end
end


return M
