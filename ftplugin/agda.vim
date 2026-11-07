
" When the ftplugin runs again for the buffer (e.g. on :edit), stop the
" Agda process of the previous instance of the module.
if exists("b:AgdaMod") && has_key(b:AgdaMod, "agda_stop")
    call b:AgdaMod.agda_stop()
endif

" Kill the cache of previously loaded "agda" module.
" Lua does this automatically, but we want a newly loaded
" module per every buffer.
lua package.loaded.agda = nil

" The name of this variable should not be changed, as it is
" hardcoded in agda/init.lua when creating bindings for prompt windows.
let b:AgdaMod = luaeval("require'agda'")

hi Todo ctermbg=DarkGray ctermfg=Black gui=NONE guibg=#353535 guifg=#efefef
" hi NonTerminating ctermbg=Red
hi NonTerminating ctermbg=LightRed ctermfg=Black gui=NONE guibg=#994444
hi NoDefinition ctermbg=Brown gui=NONE guibg=#354657
"ctermbg=LightBlue ctermfg=Black

if !exists("g:nvim_agda_settings")
    let g:nvim_agda_settings = {}
endif

" The setting is a dictionary, so far the only key in the
" dictionary is the location of the Agda binary, e.g.
" { "agda": "/usr/local/bin/agda" }
" Any key in the dictionary can be omitted, in which case,
" we are going to use hard-coded defaults.
call b:AgdaMod.setup(g:nvim_agda_settings)


" Vim commands
command! AgdaStart :call b:AgdaMod.agda_start()
command! AgdaStop :call b:AgdaMod.agda_stop()
command! AgdaLoad :call b:AgdaMod.agda_load(expand("%:p"))
command! AgdaContext :call b:AgdaMod.agda_context(expand("%:p"))
command! AgdaTypeContext :call b:AgdaMod.agda_type_context(expand("%:p"))
command! AgdaTypeContextNorm :call b:AgdaMod.agda_type_context(expand("%:p"),"Normalised")
command! AgdaTypeContextInfer :call b:AgdaMod.agda_type_context_infer(expand("%:p"))
command! AgdaInfer :call b:AgdaMod.agda_infer(expand("%:p"))
command! AgdaCompute :call b:AgdaMod.agda_compute(expand("%:p"))
command! AgdaRefine :call b:AgdaMod.agda_refine(expand("%:p"))
command! AgdaAuto :call b:AgdaMod.agda_auto(expand("%:p"))
command! AgdaSolve :call b:AgdaMod.agda_solve(expand("%:p"))
command! AgdaMakeCase :call b:AgdaMod.agda_make_case(expand("%:p"))
command! AgdaHelperFun :call b:AgdaMod.agda_helper_fun(expand("%:p"))
command! AgdaModuleContents :call b:AgdaMod.agda_module_contents(expand("%:p"))
command! AgdaWhyInscope :call b:AgdaMod.agda_why_inscope(expand("%:p"))
command! AgdaShowConstraints :call b:AgdaMod.agda_show_constraints(expand("%:p"))

command! ShowImplicit :call b:AgdaMod.show_implicit(expand("%:p"))
command! HideImplicit :call b:AgdaMod.hide_implicit(expand("%:p"))

command! MkPrompt :call b:AgdaMod.edit_goal(expand("%:p"))
command! PrintGoals :call b:AgdaMod.agda_show_goals(expand("%:p"))
command! GoalNext :call b:AgdaMod.agda_goal_next(expand("%:p"))
command! GoalPrev :call b:AgdaMod.agda_goal_prev(expand("%:p"))

command! AgdaCloseMsg :call b:AgdaMod.close_msg_win()
command! GoalContent :call b:AgdaMod.gc()
command! GetEvbuf :call b:AgdaMod.getevbuf()


" Key mappings
nnoremap <buffer> <nowait> <LocalLeader>l :<c-u>AgdaLoad<cr>
nnoremap <buffer> <nowait> <LocalLeader>q :<c-u>AgdaCloseMsg<cr>
nnoremap <buffer> <nowait> <LocalLeader>, :<c-u>AgdaTypeContext<cr>
nnoremap <buffer> <nowait> <LocalLeader>. :<c-u>AgdaTypeContextInfer<cr>
nnoremap <buffer> <nowait> <LocalLeader>u, :<c-u>AgdaTypeContextNorm<cr>
nnoremap <buffer> <nowait> <LocalLeader>d :<c-u>AgdaInfer<cr>
nnoremap <buffer> <nowait> <LocalLeader>r :<c-u>AgdaRefine<cr>
nnoremap <buffer> <nowait> <LocalLeader>c :<c-u>AgdaMakeCase<cr>
nnoremap <buffer> <nowait> <LocalLeader>n :<c-u>AgdaCompute<cr>
nnoremap <buffer> <nowait> <LocalLeader>a :<c-u>AgdaAuto<cr>
nnoremap <buffer> <nowait> <LocalLeader>s :<c-u>AgdaSolve<cr>
nnoremap <buffer> <nowait> <LocalLeader>h :<c-u>AgdaHelperFun<cr>
nnoremap <buffer> <nowait> <LocalLeader>o :<c-u>AgdaModuleContents<cr>
nnoremap <buffer> <nowait> <LocalLeader>w :<c-u>AgdaWhyInscope<cr>
nnoremap <buffer> <nowait> <LocalLeader>e :<c-u>MkPrompt<cr>
nnoremap <buffer> <nowait> <LocalLeader>? :<c-u>PrintGoals<cr>
nnoremap <buffer> <nowait> <LocalLeader>f :<c-u>GoalNext<cr>
nnoremap <buffer> <nowait> <LocalLeader>b :<c-u>GoalPrev<cr>


" mappings
runtime agda-input.vim
