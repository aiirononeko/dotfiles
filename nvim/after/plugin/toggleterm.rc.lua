local status, toggleterm = pcall(require, "toggleterm")
toggleterm.setup {
  open_mapping = [[<c-t>]],
  direction = 'float',
}

local Terminal = require('toggleterm.terminal').Terminal
local lazygit  = Terminal:new({ cmd = "lazygit", hidden = true })

function _lazygit_toggle()
  lazygit:toggle()
end

vim.api.nvim_set_keymap("n", "gt", "<cmd>lua _lazygit_toggle()<CR>", { noremap = true, silent = true })
