local status, nvimTree = pcall(require, "nvim-tree")
local keymap = vim.keymap

-- disable netrw at the very start of your init.lua (strongly advised)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

-- set termguicolors to enable highlight groups
vim.opt.termguicolors = true

nvimTree.setup({
  view = {
    width = 40
  }
})

keymap.set('n', 'nt', ':NvimTreeToggle<CR>', { noremap = true, silent = true })
