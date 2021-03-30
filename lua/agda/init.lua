local utf8 = require('lua-utf8')

local M = {}

local agda_job = nil
local goals = {}
local msg_buf = nil
local msg_win = nil

-- Helper functions
local function error(msg)
    vim.api.nvim_err_writeln(msg)
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
            print("Don't know hl-group for " .. name)
            return "Normal"
        end
    end

    for k, v in pairs(msg["info"]["payload"]) do
        local r = v["range"]
        local s = find_line(r[1])
        local e = find_line(r[2])
        local g = translate_hl_group(v["atoms"][1])
        -- We are using the direct api call here instead of
        -- vim.highlight.range(bufnr, -1, g, s, e), as we are sure
        -- that the range that Agda sends is located on the same line.
        vim.api.nvim_buf_add_highlight(bufnr, -1, g, s[1], s[2], e[2])
        --print("hl: [" .. vim.inspect(s) .. ", " .. vim.inspect(e) .. "]  ", v["atoms"][1])
    end
end


local function handle_displayinfo(msg)
    if (msg["info"]["kind"] == "Error") then
        vim.api.nvim_err_write("Error: " .. msg["info"]["message"])
    elseif msg.info.kind == "Context" then
        print(vim.inspect(msg))
        local p = {"Context",
                   "=======",
                   ""}
        for k,v in pairs(msg.info.context) do
            table.insert(p, v.originalName .. " : " .. v.binding)
        end
        mk_window (p)
        --popup.create(
        --    p,
        --    {
        --        line = msg.info.interactionPoint.range[1].start.line,
        --        col = msg.info.interactionPoint.range[1].start.col,
        --        title = "Context",
        --        border = true,
        --        minwidth = 20,
        --    })
    else
        print("Don't know how to handle DisplayInfo of kind: " 
              .. msg["info"]["kind"] .. " :: " .. vim.inspect(msg))
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
        --if l >= v["start"][1] and l <= v["end"][1]
        --   and c >= v["start"][2] and c < v["end"][2] then
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
    print("'" .. get_goal_content() .. "'")
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
    else 
        print("Don't know how to handle " .. msg["kind"]
              .. " :: " .. vim.inspect(msg))
    end
end


local function on_event(job_id, data, event)
    if event == "stdout" or event == "stderr" then
        for _ , v in pairs(data) do
            if (v ~= "JSON> " and v ~= "") then
                --print("received: " .. vim.inspect(v))
                handle_msg (vim.fn.json_decode(v))
            end
        end
    end
    -- if event == "exit" ...
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
    print("agda job is: ".. agda_job)
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
        --local g = get_goal_content(n)
        local cmd = "(Cmd_context Normalised " .. n[1]
                    .. " noRange \"\")"
        agda_feed(file, cmd)
    end
end

return M
