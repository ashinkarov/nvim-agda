
echom "Hello from ftplugin/agda"
"lua require ('agda')


let LoadCmd    = luaeval("require'agda'.agda_load")
let ContextCmd = luaeval("require'agda'.agda_context")

" Vim commands
command! AgdaStart lua require'agda'.agda_start()
command! AgdaLoad :call LoadCmd(expand("%:p"))
command! AgdaContext :call ContextCmd(expand("%:p"))

command! AgdaCloseMsg lua require'agda'.close_msg_win()
command! GoalContent lua require'agda'.gc()


" Key mappings
nm <buffer> <LocalLeader>l :<c-u>w<cr> :<c-u>AgdaLoad<cr>
" AgdaLoad<cr>
nm <buffer> <LocalLeader>q :<c-u>AgdaCloseMsg<cr>
nm <buffer> <LocalLeader>, :<c-u>AgdaContext<cr>

" mappings
noremap! <buffer> <LocalLeader>to →
