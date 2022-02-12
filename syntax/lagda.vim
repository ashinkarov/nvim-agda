
" For now we set the entire syntax to tex, but later we can
" actually describe that we apply this only to code regions. 
set syntax=tex

syn match lagdaBeginCode /\\begin{code}/ contained
syn match lagdaEndCode /\\end{code}/ contained

syn region lagdaCode start=+\\begin{code}+ end=+\\end{code}+ keepend

hi default link lagdaBeginCode  Statement
hi default link lagdaEndCode    Statement
hi default link lagdaCode       Normal

