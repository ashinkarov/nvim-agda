
" For now we set the entire syntax to tex, but later we can
" actually describe that we apply this only to code regions.
"set syntax=tex

if exists("b:current_syntax")
  finish
endif

if !exists('main_syntax')
  let main_syntax = 'lagda'
endif

runtime! syntax/tex.vim
unlet! b:current_syntax

" Here we want to match Agda code block and disable
" any hilighting inside.  Otherwise, not only we have
" conflicting hilighting of codeblocks, but also we
" run into issues such as broken math environment when
" using `$`s in Agda code.
"
" The rule below says:
"    * matchgroup:  colorise begin/end as tex statements
"    * start/end:   boundaries of the code block
"    * containedin: (crucially important!) ensure that the
"                   rule is applied in all matchgroups
syn region lagdaCode
   \ matchgroup=texStatement
   \ start=+\\begin{code}+ end=+\\end{code}+
   \ containedin=ALL

hi default link lagdaCode       Normal

let b:current_syntax = "lagda"
if main_syntax ==# 'lagda'
  unlet main_syntax
endif

