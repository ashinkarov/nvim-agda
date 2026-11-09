
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

" Comments, as in Vim's ftplugin for Haskell, which has the same syntax
" for them.  'commentstring' is used by Neovim's gc and by plugins.
setlocal comments=s1fl:{-,mb:-,ex:-},:-- commentstring=--\ %s

" The highlighting groups of the plugin, in addition to standard ones.
" They are links to standard groups, so that they fit the colour scheme,
" and defaults, so that colour schemes and users can override them.  We
" set them again when the colour scheme changes, as :colorscheme clears
" them.  Goals link to DiffAdd as it has a background in every colour
" scheme (greenish in most, like goals in the Emacs mode); problems are
" underlined like diagnostics.
function! s:Highlights()
    hi default link AgdaHole DiffAdd
    hi default link AgdaUnsolvedMeta DiagnosticUnderlineWarn
    hi default link AgdaUnsolvedConstraint AgdaUnsolvedMeta
    hi default link AgdaErrorWarning DiagnosticUnderlineError
    hi default link AgdaPositivityProblem DiagnosticUnderlineWarn
    hi default link AgdaCoverageProblem DiagnosticUnderlineWarn
    hi default link AgdaIncompletePattern DiagnosticUnderlineWarn
    hi default link AgdaInstanceProblem DiagnosticUnderlineWarn
    hi default link AgdaConfluenceProblem DiagnosticUnderlineWarn
    hi default link AgdaShadowingInTelescope DiagnosticUnderlineHint
    hi default link AgdaCosmeticProblem DiagnosticUnderlineHint
    hi default link AgdaDeadcode DiagnosticUnnecessary
    hi default link NonTerminating DiagnosticUnderlineWarn
    hi default link NoDefinition DiagnosticUnderlineWarn
endfunction
call s:Highlights()
augroup agda_highlights
    autocmd!
    autocmd ColorScheme * call s:Highlights()
augroup END

if !exists("g:nvim_agda_settings")
    let g:nvim_agda_settings = {}
endif

" The setting is a dictionary, so far the only key in the
" dictionary is the location of the Agda binary, e.g.
" { "agda": "/usr/local/bin/agda" }
" Any key in the dictionary can be omitted, in which case,
" we are going to use hard-coded defaults.
call b:AgdaMod.setup(g:nvim_agda_settings)


" CTRL-] jumps to the definition of the name under the cursor and CTRL-T
" back, using the definition sites in Agda's highlighting.
function! AgdaTagfunc(pattern, flags, info)
    return b:AgdaMod.tagfunc(a:pattern, a:flags)
endfunction
setlocal tagfunc=AgdaTagfunc
" Also on operators without an identifier after them on the line, where
" Vim's own CTRL-] fails (see `jump_to_definition`).
nnoremap <buffer> <nowait> <silent> <C-]> <Cmd>call b:AgdaMod.jump_to_definition("tag")<CR>
nnoremap <buffer> <nowait> <silent> <C-W>] <Cmd>call b:AgdaMod.jump_to_definition("stag")<CR>
nnoremap <buffer> <nowait> <silent> <C-W><C-]> <Cmd>call b:AgdaMod.jump_to_definition("stag")<CR>
nnoremap <buffer> <nowait> <silent> <C-LeftMouse> <LeftMouse><Cmd>call b:AgdaMod.jump_to_definition("tag")<CR>
nnoremap <buffer> <nowait> <silent> g<LeftMouse> <LeftMouse><Cmd>call b:AgdaMod.jump_to_definition("tag")<CR>

" The commands and the <LocalLeader> mappings (see `commands` in
" lua/agda/init.lua).
call b:AgdaMod.define_commands()


" mappings
lua require('agda.input').map(0)
