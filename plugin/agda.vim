" The state of Agda in the current buffer for 'statusline', e.g.
" "Agda: 2 goals", or "" outside Agda buffers:
"     set statusline+=%{AgdaStatus()}
" See "Status line" in the README.
function! AgdaStatus() abort
    return get(b:, 'agda_status', '')
endfunction
