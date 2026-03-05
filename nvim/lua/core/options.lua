-- netrw を無効化 (neo-tree / telescope-file-browser を使用)
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

local opt = vim.opt

-- 行番号
opt.number = true
opt.relativenumber = false

-- インデント
opt.tabstop = 2
opt.shiftwidth = 2
opt.expandtab = true
opt.smartindent = true

-- 検索
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- 表示
opt.termguicolors = true
opt.signcolumn = "yes"
opt.wrap = false
opt.scrolloff = 8

-- クリップボード
opt.clipboard = "unnamedplus"

-- ファイル
opt.swapfile = false
opt.backup = false
opt.undofile = true

-- ステータスライン
opt.laststatus = 3
