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
  files_tree = { "ファイルツリー", "File tree" },
  grep = { "テキスト検索", "Live grep" },
  buffers = { "バッファ一覧", "Find buffers" },
  tree = { "ファイルツリー切替", "Toggle file tree" },
  lazygit = { "LazyGit 起動", "Open LazyGit" },
  git_diff = { "差分ビュー (全体)", "Diff view (all files)" },
  git_diff_close = { "差分ビューを閉じる", "Close diff view" },
  git_file_history = { "ファイル履歴", "File history" },
  git_reset = { "変更リセット", "Reset hunk" },
  git_blame = { "Git Blame", "Git Blame" },
  git_next = { "次の変更箇所", "Next hunk" },
  git_prev = { "前の変更箇所", "Previous hunk" },
  claude = { "Claude Code 切替", "Toggle Claude Code" },
  claude_quit = { "Claude Code 終了", "Quit Claude Code" },
  claude_continue = { "Claude Code 続行", "Continue Claude Code" },
  claude_sessions = { "Claude セッション検索", "Claude Sessions" },
  claude_prompts = { "Claude プロンプト検索", "Claude Prompts" },
  claude_timeline = { "Claude タイムライン", "Claude Timeline" },
  claude_accept = { "Claude Accept/Reject", "Claude Accept/Reject" },
  md_toggle = { "Markdown プレビュー切替", "Toggle Markdown preview" },
  md_split = { "Markdown 分割プレビュー", "Markdown split preview" },
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
    { "<leader>F", desc = desc("files_tree") },
    { "<leader>g", desc = desc("grep") },
    { "<leader>b", desc = desc("buffers") },
    { "<leader>e", desc = desc("tree") },
    { "<leader>gg", desc = desc("lazygit") },
    { "<leader>gd", desc = desc("git_diff") },
    { "<leader>gD", desc = desc("git_diff_close") },
    { "<leader>gh", desc = desc("git_file_history") },
    { "<leader>gr", desc = desc("git_reset") },
    { "<leader>gb", desc = desc("git_blame") },
    { "]c", desc = desc("git_next") },
    { "[c", desc = desc("git_prev") },
    { "<leader>cc", desc = desc("claude") },
    { "<leader>cq", desc = desc("claude_quit") },
    { "<leader>cr", desc = desc("claude_continue") },
    { "<leader>cs", desc = desc("claude_sessions") },
    { "<leader>cp", desc = desc("claude_prompts") },
    { "<leader>ct", desc = desc("claude_timeline") },
    { "<leader>ca", desc = desc("claude_accept") },
    { "<leader>mt", desc = desc("md_toggle") },
    { "<leader>ms", desc = desc("md_split") },
    { "<leader>?", desc = desc("lang") },
  })
end

local function toggle_lang()
  lang = lang == 1 and 2 or 1
  apply_descriptions()
  vim.notify(lang == 1 and "日本語に切替" or "Switched to English", vim.log.levels.INFO)
end

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
map("n", "<leader>qq", "<cmd>qa!<CR>", { desc = desc("quit") })
map("n", "<leader>qa", "<cmd>q!<CR>", { desc = desc("quit_force") })
map("n", "<leader>w", "<cmd>w<CR>", { desc = desc("save") })
map("n", "<leader>x", "<cmd>wq<CR>", { desc = desc("savequit") })

-- WSL2用: "+レジスタ経由のクリップボード操作キーマップ
local uv = vim.uv or vim.loop
local is_wsl = vim.fn.has("wsl") == 1
  or ((uv.os_uname().release or ""):lower():find("microsoft", 1, true) ~= nil)
if is_wsl then
  map({ "n", "v" }, "<leader>y", '"+y', { desc = "クリップボードにコピー" })
  map("n", "<leader>p", '"+p', { desc = "クリップボードから貼付け" })
end

-- Markdown プレビュー (markview.nvim)
map("n", "<leader>mt", "<cmd>Markview<CR>", { desc = desc("md_toggle") })
map("n", "<leader>ms", "<cmd>Markview splitToggle<CR>", { desc = desc("md_split") })

-- 言語トグル
map("n", "<leader>?", toggle_lang, { desc = desc("lang") })

-- which-key 読み込み後に日本語の説明を適用
vim.api.nvim_create_autocmd("User", {
  pattern = "VeryLazy",
  once = true,
  callback = apply_descriptions,
})
