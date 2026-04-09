-- Minimal init for testing tiny-packupdate.nvim
vim.opt.rtp:prepend(".")
vim.opt.rtp:prepend("deps/mini.nvim")
vim.cmd("runtime plugin/tiny-packupdate.lua")
