-- Minimal init for the VHS demo recordings (see `make demo`).
-- Run from the repo root so `but status` sees this workspace.
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.o.termguicolors = true
vim.o.laststatus = 0
vim.o.cmdheight = 0
vim.o.ruler = false
vim.o.showcmd = false
vim.o.showmode = false
vim.o.number = false
vim.o.signcolumn = 'no'
vim.o.fillchars = 'eob: '
pcall(vim.cmd, 'colorscheme habamax')
require('gitbutler').setup({ kind = 'current' })
