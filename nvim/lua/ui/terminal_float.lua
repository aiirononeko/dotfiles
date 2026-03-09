local M = {}

local terminal_buf = nil
local terminal_win = nil
local terminal_chan = nil
local terminal_generation = 0

local function bump_generation()
  terminal_generation = terminal_generation + 1
  return terminal_generation
end

local function clear_state()
  terminal_buf = nil
  terminal_win = nil
  terminal_chan = nil
end

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function terminal_float_opts()
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

local function open_terminal()
  if not valid_buf(terminal_buf) then
    terminal_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[terminal_buf].bufhidden = "hide"
  end

  terminal_win = vim.api.nvim_open_win(terminal_buf, true, terminal_float_opts())

  local generation = bump_generation()
  terminal_chan = vim.fn.termopen(vim.o.shell, {
    on_exit = function()
      if generation ~= terminal_generation then
        return
      end
      clear_state()
    end,
  })

  if not terminal_chan or terminal_chan <= 0 then
    if valid_buf(terminal_buf) then
      vim.api.nvim_buf_delete(terminal_buf, { force = true })
    end
    clear_state()
    vim.notify("Failed to start terminal", vim.log.levels.ERROR)
    return nil
  end

  vim.cmd("startinsert")
  return terminal_chan
end

function M.toggle()
  if valid_win(terminal_win) then
    vim.api.nvim_win_hide(terminal_win)
    terminal_win = nil
    return
  end

  if not valid_buf(terminal_buf) then
    open_terminal()
    return
  end

  terminal_win = vim.api.nvim_open_win(terminal_buf, true, terminal_float_opts())
  vim.cmd("startinsert")
end

function M.quit()
  local chan = terminal_chan
  local buf = terminal_buf

  bump_generation()

  if chan then
    pcall(vim.fn.jobstop, chan)
  end
  if valid_buf(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  clear_state()
end

return M
