-- Minimal init for isolated testing. Use with: nvim --clean --headless -u tests/minimal_init.lua
vim.opt.rtp:prepend('.')
vim.opt.swapfile = false
vim.opt.loadplugins = false
require('gitbutler').setup()
