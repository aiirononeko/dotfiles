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

-- Vimチートシート (ステータスラインの1段上にフロート表示)
opt.laststatus = 3

local cheatsheet = {
  "gg:先頭行  G:最終行  {n}G:n行目へ",
  "w:次の単語  b:前の単語  e:単語末尾",
  "0:行頭  ^:非空白行頭  $:行末",
  "f{c}:行内で{c}へ移動  ;:次  ,:前",
  "H:画面上端  M:画面中央  L:画面下端",
  "%:対応する括弧へジャンプ",
  "Ctrl+d:半頁下  Ctrl+u:半頁上",
  "Ctrl+o:前の位置  Ctrl+i:次の位置",
  "{:前の段落  }:次の段落",
  "/{pattern}:検索  n:次  N:前",
  "*:カーソル下の単語を検索  #:逆方向",
  ":%s/old/new/g:全置換  /gc:確認付き",
  ":s/old/new/g:行内置換",
  "ciw:単語を変更  ci\":\"内を変更",
  "diw:単語を削除  di(:括弧内を削除",
  "yiw:単語をコピー  yi{:{}内をコピー",
  "dd:行削除  yy:行コピー  p:貼付け",
  "o:下に行挿入  O:上に行挿入",
  "A:行末に追記  I:行頭に挿入",
  "u:取消  Ctrl+r:やり直し",
  ".:直前の操作を繰返す",
  ">>:インデント  <<:アンインデント",
  "J:次の行を結合",
  "v:選択  V:行選択  Ctrl+v:矩形選択",
  "viw:単語選択  vi\":\"内を選択",
  "qa:マクロ記録開始(a)  q:停止  @a:再生",
  "ZZ:保存して閉じる  ZQ:保存せず閉じる",
  ":!{cmd}:外部コマンド実行",
  "gd:定義へ移動  K:ドキュメント表示",
  "Ctrl+a:数値+1  Ctrl+x:数値-1",
  "~:大文字/小文字切替  gU:大文字化  gu:小文字化",
}

math.randomseed(os.time())

local function pick_tips(n)
  local indices = {}
  local picked = {}
  while #picked < n and #picked < #cheatsheet do
    local i = math.random(#cheatsheet)
    if not indices[i] then
      indices[i] = true
      picked[#picked + 1] = cheatsheet[i]
    end
  end
  return picked
end

local tip_buf = nil
local tip_win = nil

local function update_tip_window()
  if not tip_buf or not vim.api.nvim_buf_is_valid(tip_buf) then return end
  local width = vim.o.columns
  local text = "  " .. table.concat(pick_tips(2), "  |  ")
  -- 幅に合わせてパディング
  if #text < width then
    text = text .. string.rep(" ", width - #text)
  end
  vim.api.nvim_buf_set_lines(tip_buf, 0, -1, false, { text })
end

local function open_tip_window()
  if tip_win and vim.api.nvim_win_is_valid(tip_win) then
    vim.api.nvim_win_close(tip_win, true)
  end
  tip_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[tip_buf].bufhidden = "wipe"

  local width = vim.o.columns
  -- ステータスラインの1段上 (row = lines - 3: cmdline=1 + statusline=1 + this=1)
  tip_win = vim.api.nvim_open_win(tip_buf, false, {
    relative = "editor",
    row = vim.o.lines - 3,
    col = 0,
    width = width,
    height = 1,
    style = "minimal",
    focusable = false,
    zindex = 1,
  })

  -- 見た目をステータスラインに馴染ませる
  vim.api.nvim_set_hl(0, "CheatBar", { bg = "#1a1b26", fg = "#7aa2f7" })
  vim.api.nvim_win_set_option(tip_win, "winhl", "Normal:CheatBar")

  update_tip_window()
end

-- UI起動後にウィンドウ作成
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.defer_fn(open_tip_window, 50)
  end,
})

-- リサイズ時に再作成
vim.api.nvim_create_autocmd("VimResized", {
  callback = open_tip_window,
})

-- 30秒ごとにヒントを入れ替え
local timer = vim.loop.new_timer()
timer:start(30000, 30000, vim.schedule_wrap(update_tip_window))
