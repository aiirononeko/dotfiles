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

-- フロートコマンドパレット
local function open_command_palette()
  local commands = {
    { key = "q", label = "q  - 閉じる", cmd = "q" },
    { key = "w", label = "w  - 保存", cmd = "w" },
    { key = "x", label = "wq - 保存して閉じる", cmd = "wq" },
  }

  local lines = {}
  for _, c in ipairs(commands) do
    table.insert(lines, "  " .. c.label)
  end

  local width = 24
  local height = #lines + 2
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
  vim.api.nvim_buf_set_lines(buf, 1, -1, false, lines)
  vim.api.nvim_buf_set_lines(buf, #lines + 1, -1, false, { "" })

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Command ",
    title_pos = "center",
  })

  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  for _, c in ipairs(commands) do
    vim.keymap.set("n", c.key, function()
      close()
      vim.cmd(c.cmd)
    end, { buffer = buf, nowait = true })
  end

  vim.keymap.set("n", "<Esc>", close, { buffer = buf, nowait = true })
  vim.keymap.set("n", "<leader>", close, { buffer = buf, nowait = true })
end

map("n", "<leader><leader>", open_command_palette, { desc = "Command palette" })
