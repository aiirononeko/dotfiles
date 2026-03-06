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

-- WSL2: win32yank.exe を使ったクリップボード連携
local uv = vim.uv or vim.loop
local is_wsl = vim.fn.has("wsl") == 1
  or ((uv.os_uname().release or ""):lower():find("microsoft", 1, true) ~= nil)

if is_wsl then
  local win32yank = vim.fn.exepath("win32yank.exe")
  if win32yank ~= "" then
    vim.g.clipboard = {
      name = "WslClipboard",
      copy = {
        ["+"] = { win32yank, "-i", "--crlf" },
        ["*"] = { win32yank, "-i", "--crlf" },
      },
      paste = {
        ["+"] = { win32yank, "-o", "--lf" },
        ["*"] = { win32yank, "-o", "--lf" },
      },
      cache_enabled = 0,
    }
  end
end

-- ファイル
opt.swapfile = false
opt.backup = false
opt.undofile = true

-- ステータスライン
opt.laststatus = 3
