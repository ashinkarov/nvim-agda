" The input sequences for Unicode characters (see lua/agda/input.lua) in
" the current buffer.  The ftplugin sets them in Agda buffers; this file
" is for other buffers, e.g. with :runtime agda-input.vim.
lua require('agda.input').map(0)
