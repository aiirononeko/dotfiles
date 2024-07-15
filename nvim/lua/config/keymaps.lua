local Util = require("lazyvim.util")
local map = vim.keymap.set

vim.keymap.set("i", "jj", "<ESC>", { silent = true })

-- floating terminal
local lazyterm = function()
  Util.terminal(nil, { cwd = Util.root(), border = "rounded" })
end
map("n", "<leader>ft", lazyterm, { desc = "Terminal (Root Dir)" })
map("n", "<leader>fT", function()
  Util.terminal()
end, { desc = "Terminal (cwd)" })
map("n", "<c-/>", lazyterm, { desc = "Terminal (Root Dir)" })
map("n", "<c-_>", lazyterm, { desc = "which_key_ignore" })
