
let AgdaMod = luaeval("require'agda'")

call AgdaMod.setup({"agda": "/home/tema/.local/bin/agda"})


" Vim commands
command! AgdaStart :call AgdaMod.agda_start()
command! AgdaLoad :call AgdaMod.agda_load(expand("%:p"))
command! AgdaContext :call AgdaMod.agda_context(expand("%:p"))
command! AgdaTypeContext :call AgdaMod.agda_type_context(expand("%:p"))
command! AgdaInfer :call AgdaMod.agda_infer(expand("%:p"))
command! AgdaCompute :call AgdaMod.agda_compute(expand("%:p"))
command! AgdaRefine :call AgdaMod.agda_refine(expand("%:p"))
command! AgdaAuto :call AgdaMod.agda_auto(expand("%:p"))
command! AgdaMakeCase :call AgdaMod.agda_make_case(expand("%:p"))
command! AgdaHelperFun :call AgdaMod.agda_helper_fun(expand("%:p"))
command! ToggleImplicit :call AgdaMod.toggle_implicit(expand("%:p"))
command! MkPrompt :call AgdaMod.edit_goal(expand("%:p"))
command! PrintGoals :call AgdaMod.agda_show_goals(expand("%:p"))
command! GoalNext :call AgdaMod.agda_goal_next(expand("%:p"))
command! GoalPrev :call AgdaMod.agda_goal_prev(expand("%:p"))

command! AgdaCloseMsg :call AgdaMod.close_msg_win()
command! GoalContent :call AgdaMod.gc()
command! GetEvbuf :call AgdaMod.getevbuf()


" Key mappings
nm <buffer> <LocalLeader>l :<c-u>AgdaLoad<cr>
nm <buffer> <LocalLeader>q :<c-u>AgdaCloseMsg<cr>
nm <buffer> <LocalLeader>, :<c-u>AgdaTypeContext<cr>
nm <buffer> <LocalLeader>d :<c-u>AgdaInfer<cr>
nm <buffer> <LocalLeader>r :<c-u>AgdaRefine<cr>
nm <buffer> <LocalLeader>c :<c-u>AgdaMakeCase<cr>
nm <buffer> <LocalLeader>n :<c-u>AgdaCompute<cr>
nm <buffer> <LocalLeader>a :<c-u>AgdaAuto<cr>
nm <buffer> <LocalLeader>h :<c-u>AgdaHelperFun<cr>
nm <buffer> <LocalLeader>e :<c-u>MkPrompt<cr>
nm <buffer> <LocalLeader>? :<c-u>PrintGoals<cr>
nm <buffer> <LocalLeader>f :<c-u>GoalNext<cr>
nm <buffer> <LocalLeader>b :<c-u>GoalPrev<cr>

" mappings
runtime agda-input.vim
