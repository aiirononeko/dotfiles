local map = vim.keymap.set

local M = {}

local claude_buf = nil
local claude_win = nil
local claude_chan = nil
local claude_generation = 0

local function bump_generation()
  claude_generation = claude_generation + 1
  return claude_generation
end

local function clear_state()
  claude_buf = nil
  claude_win = nil
  claude_chan = nil
end

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

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

local function is_job_running(job_id)
  if not job_id then
    return false
  end

  local ok, result = pcall(vim.fn.jobwait, { job_id }, 0)
  return ok and type(result) == "table" and result[1] == -1
end

local function send_prompt(chan, prompt)
  if not chan or chan <= 0 or type(prompt) ~= "string" or prompt == "" then
    return
  end

  vim.defer_fn(function()
    if is_job_running(chan) then
      vim.fn.chansend(chan, prompt)
      if prompt:sub(-1) ~= "\n" then
        vim.fn.chansend(chan, "\n")
      end
    end
  end, 120)
end

local function open_claude(cmd, opts)
  if type(cmd) ~= "table" or #cmd == 0 then
    vim.notify("Claude command must be a non-empty argv list", vim.log.levels.ERROR)
    return nil
  end
  opts = opts or {}

  if not valid_buf(claude_buf) then
    claude_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[claude_buf].bufhidden = "hide"
  end

  claude_win = vim.api.nvim_open_win(claude_buf, true, claude_float_opts())

  local generation = bump_generation()
  claude_chan = vim.fn.termopen(cmd, {
    cwd = opts.cwd,
    on_exit = function()
      if generation ~= claude_generation then
        return
      end
      clear_state()
    end,
  })

  if not claude_chan or claude_chan <= 0 then
    if valid_buf(claude_buf) then
      vim.api.nvim_buf_delete(claude_buf, { force = true })
    end
    clear_state()
    vim.notify("Failed to start Claude Code", vim.log.levels.ERROR)
    return nil
  end

  vim.cmd("startinsert")
  send_prompt(claude_chan, opts.prompt)
  return claude_chan
end

local function claude_toggle()
  if valid_win(claude_win) then
    vim.api.nvim_win_hide(claude_win)
    claude_win = nil
    return
  end

  if not valid_buf(claude_buf) then
    open_claude({ "claude" })
    return
  end

  claude_win = vim.api.nvim_open_win(claude_buf, true, claude_float_opts())
  vim.cmd("startinsert")
end

local function claude_quit()
  local chan = claude_chan
  local buf = claude_buf

  bump_generation()

  if chan then
    pcall(vim.fn.jobstop, chan)
  end
  if valid_buf(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  clear_state()
end

local function claude_new()
  claude_quit()
  return open_claude({ "claude" })
end

local function claude_continue()
  claude_quit()
  return open_claude({ "claude", "--continue" })
end

local function claude_resume(session_id)
  if type(session_id) ~= "string" or session_id == "" then
    vim.notify("session_id is required for Claude resume", vim.log.levels.ERROR)
    return nil
  end

  claude_quit()
  return open_claude({ "claude", "--resume", session_id })
end

local function claude_launch_prompt(prompt, opts)
  opts = opts or {}

  local cmd = { "claude" }
  if type(opts.session_id) == "string" and opts.session_id ~= "" then
    cmd = { "claude", "--resume", opts.session_id }
  elseif opts.continue_session then
    cmd = { "claude", "--continue" }
  end

  claude_quit()
  return open_claude(cmd, {
    cwd = opts.cwd,
    prompt = prompt,
  })
end

local function claude_is_active()
  return is_job_running(claude_chan)
end

M.toggle = claude_toggle
M.quit = claude_quit
M.new = claude_new
M.continue = claude_continue
M.resume = claude_resume
M.launch_prompt = claude_launch_prompt
M.is_active = claude_is_active

map("n", "<leader>cc", M.toggle, { desc = "Claude Code 切替" })
map("t", "<leader>cc", M.toggle, { desc = "Claude Code 切替" })
map("n", "<leader>cq", M.quit, { desc = "Claude Code 終了" })
map("n", "<leader>cr", M.continue, { desc = "Claude Code 続行" })
map("t", "<leader>cr", M.continue, { desc = "Claude Code 続行" })

return M
