
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

function! LogAgda(name, text, append)
    let agdawinnr = bufwinnr('__Agda__')
    let prevwinnr = winnr()
    if agdawinnr == -1
        let eventignore_save = &eventignore
        set eventignore=all

        silent keepalt botright 8split __Agda__

        let &eventignore = eventignore_save
        setlocal noreadonly
        setlocal buftype=nofile
        setlocal bufhidden=hide
        setlocal noswapfile
        setlocal nobuflisted
        setlocal nolist
        setlocal nonumber
        setlocal nowrap
        setlocal textwidth=0
        setlocal nocursorline
        setlocal nocursorcolumn

        if exists('+relativenumber')
            setlocal norelativenumber
        endif
    else
        let eventignore_save = &eventignore
        set eventignore=BufEnter

        execute agdawinnr . 'wincmd w'
        let &eventignore = eventignore_save
    endif

    let lazyredraw_save = &lazyredraw
    set lazyredraw
    let eventignore_save = &eventignore
    set eventignore=all

    let &l:statusline = a:name
    if a:append == 'True'
        silent put =a:text
    else
        silent %delete _
        silent 0put =a:text
    endif

    0

    let &lazyredraw = lazyredraw_save
    let &eventignore = eventignore_save

    let eventignore_save = &eventignore
    set eventignore=BufEnter

    execute prevwinnr . 'wincmd w'
    let &eventignore = eventignore_save
endfunction



" Vim commands
command! AgdaStart :call b:AgdaMod.agda_start()
command! AgdaLoad :call b:AgdaMod.agda_load(expand("%:p"))
command! AgdaContext :call b:AgdaMod.agda_context(expand("%:p"))
command! AgdaTypeContext :call b:AgdaMod.agda_type_context(expand("%:p"))
command! AgdaTypeContextNorm :call b:AgdaMod.agda_type_context(expand("%:p"),"Normalised")
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
nm <buffer> <LocalLeader>l :<c-u>AgdaLoad<cr>
nm <buffer> <LocalLeader>q :<c-u>AgdaCloseMsg<cr>
nm <buffer> <LocalLeader>, :<c-u>AgdaTypeContext<cr>
nm <buffer> <LocalLeader>u, :<c-u>AgdaTypeContextNorm<cr>
nm <buffer> <LocalLeader>d :<c-u>AgdaInfer<cr>
nm <buffer> <LocalLeader>r :<c-u>AgdaRefine<cr>
nm <buffer> <LocalLeader>c :<c-u>AgdaMakeCase<cr>
nm <buffer> <LocalLeader>n :<c-u>AgdaCompute<cr>
nm <buffer> <LocalLeader>a :<c-u>AgdaAuto<cr>
nm <buffer> <LocalLeader>s :<c-u>AgdaSolve<cr>
nm <buffer> <LocalLeader>h :<c-u>AgdaHelperFun<cr>
nm <buffer> <LocalLeader>o :<c-u>AgdaModuleContents<cr>
nm <buffer> <LocalLeader>w :<c-u>AgdaWhyInscope<cr>
nm <buffer> <LocalLeader>e :<c-u>MkPrompt<cr>
nm <buffer> <LocalLeader>? :<c-u>PrintGoals<cr>
nm <buffer> <LocalLeader>f :<c-u>GoalNext<cr>
nm <buffer> <LocalLeader>b :<c-u>GoalPrev<cr>


" mappings
runtime agda-input.vim
