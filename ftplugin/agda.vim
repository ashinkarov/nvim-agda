
echom "Hello from ftplugin/agda"
"lua require ('agda')


let LoadCmd    = luaeval("require'agda'.agda_load")
let ContextCmd = luaeval("require'agda'.agda_context")
let InferCmd   = luaeval("require'agda'.agda_infer")
let RefineCmd  = luaeval("require'agda'.agda_refine")

" Vim commands
command! AgdaStart lua require'agda'.agda_start()
command! AgdaLoad :call LoadCmd(expand("%:p"))
command! AgdaContext :call ContextCmd(expand("%:p"))
command! AgdaInfer :call InferCmd(expand("%:p"))
command! AgdaRefine :call RefineCmd(expand("%:p"))

command! AgdaCloseMsg lua require'agda'.close_msg_win()
command! GoalContent lua require'agda'.gc()
command! GetEvbuf lua require'agda'.getevbuf()


" Key mappings
nm <buffer> <LocalLeader>l :<c-u>w<cr>:AgdaLoad<cr>
" AgdaLoad<cr>
nm <buffer> <LocalLeader>q :<c-u>AgdaCloseMsg<cr>
nm <buffer> <LocalLeader>, :<c-u>AgdaContext<cr>
nm <buffer> <LocalLeader>t :<c-u>AgdaInfer<cr>
nm <buffer> <LocalLeader>r :<c-u>AgdaRefine<cr>

" mappings
noremap! <buffer> <LocalLeader>to →
