vim.g.mapleader = " "
vim.g.maplocalleader = " "

local map = vim.keymap.set

-- 説明文の定義 (日本語 / English)
local descriptions = {
  jj = { "インサートモード解除", "Exit insert mode" },
  win_h = { "← ウィンドウ移動", "Move to left window" },
  win_j = { "↓ ウィンドウ移動", "Move to lower window" },
  win_k = { "↑ ウィンドウ移動", "Move to upper window" },
  win_l = { "→ ウィンドウ移動", "Move to right window" },
  nohl = { "検索ハイライト消去", "Clear search highlight" },
  quit = { "閉じる", "Quit" },
  quit_force = { "保存せず閉じる", "Quit without saving" },
  save = { "保存", "Save" },
  savequit = { "保存して閉じる", "Save and quit" },
  files = { "ファイル検索", "Find files" },
  grep = { "テキスト検索", "Live grep" },
  buffers = { "バッファ一覧", "Find buffers" },
  tree = { "ファイルツリー切替", "Toggle file tree" },
  lazygit = { "LazyGit 起動", "Open LazyGit" },
  claude = { "Claude Code 切替", "Toggle Claude Code" },
  claude_quit = { "Claude Code 終了", "Quit Claude Code" },
  lang = { "説明を英語に切替", "Switch to Japanese" },
}

-- 現在の言語 (1=日本語, 2=English)
local lang = 1

local function desc(key)
  return descriptions[key][lang]
end

local function apply_descriptions()
  local wk = require("which-key")
  wk.add({
    { "<leader>h", desc = desc("nohl") },
    { "<leader>qq", desc = desc("quit") },
    { "<leader>qa", desc = desc("quit_force") },
    { "<leader>w", desc = desc("save") },
    { "<leader>x", desc = desc("savequit") },
    { "<leader>f", desc = desc("files") },
    { "<leader>g", desc = desc("grep") },
    { "<leader>b", desc = desc("buffers") },
    { "<leader>e", desc = desc("tree") },
    { "<leader>gg", desc = desc("lazygit") },
    { "<leader>cc", desc = desc("claude") },
    { "<leader>cq", desc = desc("claude_quit") },
    { "<leader>?", desc = desc("lang") },
  })
end

local function toggle_lang()
  lang = lang == 1 and 2 or 1
  apply_descriptions()
  vim.notify(lang == 1 and "日本語に切替" or "Switched to English", vim.log.levels.INFO)
end

-- Claude Code フローティングターミナル
local claude_buf = nil
local claude_win = nil
local claude_chan = nil

local function claude_float_opts()
  local height = math.floor(0.8 * vim.o.lines)
  local width = math.floor(0.8 * vim.o.columns)
  return {
    relative = "editor",
    row = math.floor(0.5 * (vim.o.lines - height)),
    col = math.floor(0.5 * (vim.o.columns - width)),
    height = height,
    width = width,
    style = "minimal",
    border = "rounded",
  }
end

local function claude_toggle()
  -- ウィンドウが開いていたら閉じるだけ (プロセスは生存)
  if claude_win and vim.api.nvim_win_is_valid(claude_win) then
    vim.api.nvim_win_hide(claude_win)
    claude_win = nil
    return
  end

  -- バッファが無い or 削除済みなら新規作成
  if not claude_buf or not vim.api.nvim_buf_is_valid(claude_buf) then
    claude_buf = vim.api.nvim_create_buf(false, true)
    claude_win = vim.api.nvim_open_win(claude_buf, true, claude_float_opts())
    claude_chan = vim.fn.termopen("claude", {
      on_exit = function()
        claude_buf = nil
        claude_win = nil
        claude_chan = nil
      end,
    })
  else
    -- バッファは生きているのでウィンドウだけ再表示
    claude_win = vim.api.nvim_open_win(claude_buf, true, claude_float_opts())
  end

  vim.cmd("startinsert")
end

local function claude_quit()
  if claude_chan then
    vim.fn.jobstop(claude_chan)
  end
  if claude_buf and vim.api.nvim_buf_is_valid(claude_buf) then
    vim.api.nvim_buf_delete(claude_buf, { force = true })
  end
  claude_buf = nil
  claude_win = nil
  claude_chan = nil
end

map("n", "<leader>cc", claude_toggle, { desc = "Claude Code 切替" })
map("t", "<leader>cc", claude_toggle, { desc = "Claude Code 切替" })
map("n", "<leader>cq", claude_quit, { desc = "Claude Code 終了" })

-- jj でノーマルモードに戻る
map("i", "jj", "<ESC>", { desc = desc("jj") })

-- ウィンドウ移動
map("n", "<C-h>", "<C-w>h", { desc = desc("win_h") })
map("n", "<C-j>", "<C-w>j", { desc = desc("win_j") })
map("n", "<C-k>", "<C-w>k", { desc = desc("win_k") })
map("n", "<C-l>", "<C-w>l", { desc = desc("win_l") })

-- 検索ハイライトクリア
map("n", "<leader>h", "<cmd>nohlsearch<CR>", { desc = desc("nohl") })

-- ファイル操作
map("n", "<leader>qq", "<cmd>q<CR>", { desc = desc("quit") })
map("n", "<leader>qa", "<cmd>q!<CR>", { desc = desc("quit_force") })
map("n", "<leader>w", "<cmd>w<CR>", { desc = desc("save") })
map("n", "<leader>x", "<cmd>wq<CR>", { desc = desc("savequit") })

-- 言語トグル
map("n", "<leader>?", toggle_lang, { desc = desc("lang") })

-- which-key 読み込み後に日本語の説明を適用
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = apply_descriptions,
})
