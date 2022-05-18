
" Set the entire syntax to markdown and ensure that we
" do not colorise ```-regions, as agda mode would do this
" for us.
set syntax=markdown


syn match lagdaBeginCode /\s*```(agda)?/ contained
syn match lagdaEndCode /\s*```(agda)?/ contained
 
syn region lagdaCode start=/```(agda)?/  end=/```(agda)?/ keepend
 
hi default link lagdaBeginCode  Statement
hi default link lagdaEndCode    Statement
hi default link lagdaCode       Normal
