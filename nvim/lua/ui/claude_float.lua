local map = vim.keymap.set

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
