local index = require("claude.session_index")

local M = {}

local state = {
  session_id = nil,
  changes = nil,
  current_idx = 0,
  statuses = {}, -- idx -> "accepted" | "rejected" | nil
  list_buf = nil,
  list_win = nil,
}

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local content = fd:read("*a")
  fd:close()
  return content
end

local function write_file(path, content)
  local fd = io.open(path, "w")
  if not fd then
    return false
  end
  fd:write(content)
  fd:close()
  return true
end

local function apply_patch_to_original(original, patch)
  if not original or not patch then
    return nil
  end
  local lines = vim.split(original, "\n", { plain = true })
  -- Apply hunks in reverse order to avoid offset issues
  local hunks = {}
  for i, hunk in ipairs(patch) do
    hunks[i] = hunk
  end

  for i = #hunks, 1, -1 do
    local hunk = hunks[i]
    local old_start = hunk.oldStart or 1
    local old_lines_count = hunk.oldLines or 0
    local new_lines = {}

    if hunk.lines then
      for _, line in ipairs(hunk.lines) do
        local prefix = line:sub(1, 1)
        local text = line:sub(2)
        if prefix == "+" then
          new_lines[#new_lines + 1] = text
        elseif prefix == "-" then
          -- skip removed lines
        else
          new_lines[#new_lines + 1] = text
        end
      end
    end

    -- Replace old lines with new lines
    local before = {}
    for j = 1, old_start - 1 do
      before[#before + 1] = lines[j]
    end
    local after = {}
    for j = old_start + old_lines_count, #lines do
      after[#after + 1] = lines[j]
    end

    lines = {}
    for _, l in ipairs(before) do
      lines[#lines + 1] = l
    end
    for _, l in ipairs(new_lines) do
      lines[#lines + 1] = l
    end
    for _, l in ipairs(after) do
      lines[#lines + 1] = l
    end
  end

  return table.concat(lines, "\n")
end

local function can_safely_reject(change)
  if not change.original then
    return false, "originalFile が存在しません"
  end

  if change.kind == "create" then
    return true, nil
  end

  local current = read_file(change.path)
  if not current then
    return false, "ファイルが存在しません"
  end

  local claude_result = apply_patch_to_original(change.original, change.patch)
  if claude_result and current ~= claude_result then
    return false, "ユーザーによる追加変更が検出されました。Rejectするとその変更も失われます。"
  end

  return true
end

local function close_ui()
  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    vim.api.nvim_win_close(state.list_win, true)
  end
  if state.list_buf and vim.api.nvim_buf_is_valid(state.list_buf) then
    vim.api.nvim_buf_delete(state.list_buf, { force = true })
  end
  state.list_buf = nil
  state.list_win = nil
  state.session_id = nil
  state.changes = nil
  state.current_idx = 0
  state.statuses = {}
end

local function status_icon(idx)
  local s = state.statuses[idx]
  if s == "accepted" then
    return "[A]"
  elseif s == "rejected" then
    return "[R]"
  else
    return "[ ]"
  end
end

local function refresh_list()
  if not state.list_buf or not vim.api.nvim_buf_is_valid(state.list_buf) then
    return
  end

  local lines = { " Accept/Reject  (a/r/A/R/n/p/q)", string.rep("─", 33) }
  for i, c in ipairs(state.changes) do
    local kind_icon = c.kind == "create" and "+" or "~"
    lines[#lines + 1] = string.format(" %s %s %s", status_icon(i), kind_icon, c.path)
  end

  if #state.changes == 0 then
    lines[#lines + 1] = "  (no changes)"
  end

  vim.bo[state.list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
  vim.bo[state.list_buf].modifiable = false

  -- Highlight via extmarks
  local ns = vim.api.nvim_create_namespace("claude_accept_reject")
  vim.api.nvim_buf_clear_namespace(state.list_buf, ns, 0, -1)

  vim.api.nvim_buf_set_extmark(state.list_buf, ns, 0, 0, {
    end_row = 1,
    hl_group = "Title",
    hl_eol = true,
  })

  for i, _ in ipairs(state.changes) do
    local line_nr = i + 1 -- offset for header
    local s = state.statuses[i]
    local hl = "Normal"
    if s == "accepted" then
      hl = "DiagnosticOk"
    elseif s == "rejected" then
      hl = "DiagnosticError"
    end
    vim.api.nvim_buf_set_extmark(state.list_buf, ns, line_nr, 0, {
      end_row = line_nr + 1,
      hl_group = hl,
      hl_eol = true,
    })
  end
end

local function accept_file(idx)
  if not state.changes or not state.changes[idx] then
    return
  end
  state.statuses[idx] = "accepted"
  vim.notify(" Accepted: " .. state.changes[idx].path, vim.log.levels.INFO)
  refresh_list()
end

local function reject_file(idx)
  if not state.changes or not state.changes[idx] then
    return
  end

  local change = state.changes[idx]

  if change.kind == "create" then
    local choice = vim.fn.confirm(
      "新規作成ファイルをRejectするとファイルが削除されます。\n" .. change.path .. "\n\n本当にRejectしますか？",
      "&Yes\n&No",
      2
    )
    if choice ~= 1 then
      return
    end
    vim.fn.delete(change.path)
    state.statuses[idx] = "rejected"
    vim.notify(" Rejected (deleted): " .. change.path, vim.log.levels.WARN)
    refresh_list()
    return
  end

  local safe, msg = can_safely_reject(change)
  if not safe then
    if msg then
      local choice = vim.fn.confirm(msg .. "\n本当にRejectしますか？", "&Yes\n&No", 2)
      if choice ~= 1 then
        return
      end
    else
      return
    end
  end

  if change.original then
    write_file(change.path, change.original)
    vim.cmd("checktime")
    state.statuses[idx] = "rejected"
    vim.notify(" Rejected: " .. change.path, vim.log.levels.WARN)
  end

  refresh_list()
end

local function accept_all()
  if not state.changes then
    return
  end
  for i = 1, #state.changes do
    if not state.statuses[i] then
      accept_file(i)
    end
  end
end

local function reject_all()
  if not state.changes then
    return
  end
  local choice = vim.fn.confirm("全ファイルをRejectしますか？", "&Yes\n&No", 2)
  if choice ~= 1 then
    return
  end
  for i = 1, #state.changes do
    if not state.statuses[i] then
      reject_file(i)
    end
  end
end

local function get_current_idx()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  return row - 2 -- offset for 2 header lines
end

function M.show(session_id)
  if not session_id or session_id == "" then
    vim.notify("session_id is required", vim.log.levels.ERROR)
    return
  end

  close_ui()

  local changes = index.get_changes(session_id)
  state.session_id = session_id
  state.changes = changes
  state.statuses = {}

  state.list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.list_buf].buftype = "nofile"
  vim.bo[state.list_buf].filetype = "ClaudeAcceptReject"
  vim.bo[state.list_buf].bufhidden = "wipe"

  vim.cmd("topleft 40vsplit")
  state.list_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.list_win, state.list_buf)
  vim.wo[state.list_win].number = false
  vim.wo[state.list_win].relativenumber = false
  vim.wo[state.list_win].signcolumn = "no"
  vim.wo[state.list_win].winfixwidth = true

  refresh_list()

  local buf = state.list_buf

  -- a: accept current file
  vim.keymap.set("n", "a", function()
    local idx = get_current_idx()
    if idx >= 1 and idx <= #state.changes then
      accept_file(idx)
    end
  end, { buffer = buf, desc = "Accept ファイル" })

  -- r: reject current file
  vim.keymap.set("n", "r", function()
    local idx = get_current_idx()
    if idx >= 1 and idx <= #state.changes then
      reject_file(idx)
    end
  end, { buffer = buf, desc = "Reject ファイル" })

  -- A: accept all
  vim.keymap.set("n", "A", function()
    accept_all()
  end, { buffer = buf, desc = "Accept All" })

  -- R: reject all
  vim.keymap.set("n", "R", function()
    reject_all()
  end, { buffer = buf, desc = "Reject All" })

  -- n: next file
  vim.keymap.set("n", "n", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local max_row = #state.changes + 2
    if row < max_row then
      vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
    end
  end, { buffer = buf, desc = "次のファイル" })

  -- p: prev file
  vim.keymap.set("n", "p", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    if row > 3 then
      vim.api.nvim_win_set_cursor(0, { row - 1, 0 })
    end
  end, { buffer = buf, desc = "前のファイル" })

  -- <CR>: open diff for current file
  vim.keymap.set("n", "<CR>", function()
    local idx = get_current_idx()
    if idx >= 1 and idx <= #state.changes then
      require("claude.diff").show(state.session_id)
    end
  end, { buffer = buf, desc = "Diff を表示" })

  -- q: close
  vim.keymap.set("n", "q", function()
    close_ui()
  end, { buffer = buf, desc = "閉じる" })

  -- Position cursor on first file
  if #changes > 0 then
    vim.api.nvim_win_set_cursor(state.list_win, { 3, 0 })
  end
end

-- Global keymap
vim.keymap.set("n", "<leader>ca", function()
  local sessions = index.list_sessions(vim.fn.getcwd())
  if #sessions == 0 then
    vim.notify("No Claude sessions found", vim.log.levels.WARN)
    return
  end
  M.show(sessions[1].id)
end, { desc = "Claude Accept/Reject" })

return M
