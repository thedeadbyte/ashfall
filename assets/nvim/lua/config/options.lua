-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Shipped by ashfall. ~/.config/nvim is recreated at every login, so to
-- customize, point ashfall.dev.lazyvim.configDir at your own copy.

-- No language providers are needed by LazyVim; keep :checkhealth quiet.
vim.g.loaded_python3_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

-- Share the system clipboard (wl-clipboard is installed by ashfall.dev).
vim.opt.clipboard = "unnamedplus"
