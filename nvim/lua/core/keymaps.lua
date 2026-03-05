vim.g.mapleader = " "
vim.g.maplocalleader = " "

local map = vim.keymap.set

-- jj でノーマルモードに戻る
map("i", "jj", "<ESC>", { desc = "Exit insert mode" })

-- ウィンドウ移動
map("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
map("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
map("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
map("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })

-- 検索ハイライトクリア
map("n", "<leader>h", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
