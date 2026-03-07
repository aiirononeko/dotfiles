local index = require("claude.session_index")

local M = {}

local ns = vim.api.nvim_create_namespace("claude_hunk_ar")

local hunk_state = {
  change = nil,
  hunks = nil,
  statuses = {}, -- hunk_idx -> "accepted" | "rejected" | nil
  buf = nil,
  orig_buf = nil,
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

local function clear_state()
  hunk_state.change = nil
  hunk_state.hunks = nil
  hunk_state.statuses = {}
  hunk_state.buf = nil
  hunk_state.orig_buf = nil
end

local function place_extmarks()
  if not hunk_state.buf or not vim.api.nvim_buf_is_valid(hunk_state.buf) then
    return
  end

  vim.api.nvim_buf_clear_namespace(hunk_state.buf, ns, 0, -1)

  if not hunk_state.hunks then
    return
  end

  local file_content = read_file(hunk_state.change.path)
  if not file_content then
    return
  end

  for i, hunk in ipairs(hunk_state.hunks) do
    local new_start = (hunk.newStart or 1) - 1 -- 0-indexed
    local status = hunk_state.statuses[i]
    local label
    if status == "accepted" then
      label = " [Accepted]"
    elseif status == "rejected" then
      label = " [Rejected]"
    else
      label = string.format(" [%d] Accept(a) / Reject(r)", i)
    end

    local hl = "Comment"
    if status == "accepted" then
      hl = "DiagnosticOk"
    elseif status == "rejected" then
      hl = "DiagnosticError"
    end

    pcall(vim.api.nvim_buf_set_extmark, hunk_state.buf, ns, new_start, 0, {
      virt_text = { { label, hl } },
      virt_text_pos = "eol",
    })
  end
end

local function reject_single_hunk(hunk_idx)
  local change = hunk_state.change
  if not change or not change.patch then
    return
  end

  local hunk = change.patch[hunk_idx]
  if not hunk or not hunk.lines then
    return
  end

  local content = read_file(change.path)
  if not content then
    return
  end

  local lines = vim.split(content, "\n", { plain = true })

  -- Compute what the new lines from this hunk look like
  local new_lines_in_hunk = {}
  local old_lines_in_hunk = {}

  for _, line in ipairs(hunk.lines) do
    local prefix = line:sub(1, 1)
    local text = line:sub(2)
    if prefix == "+" then
      new_lines_in_hunk[#new_lines_in_hunk + 1] = text
    elseif prefix == "-" then
      old_lines_in_hunk[#old_lines_in_hunk + 1] = text
    else
      new_lines_in_hunk[#new_lines_in_hunk + 1] = text
      old_lines_in_hunk[#old_lines_in_hunk + 1] = text
    end
  end

  -- Find the new content range in current file
  local new_start = hunk.newStart or 1
  local new_count = hunk.newLines or #new_lines_in_hunk

  -- Replace new lines with old lines (reverse the change)
  local result = {}
  for j = 1, new_start - 1 do
    result[#result + 1] = lines[j]
  end
  for _, l in ipairs(old_lines_in_hunk) do
    result[#result + 1] = l
  end
  for j = new_start + new_count, #lines do
    result[#result + 1] = lines[j]
  end

  write_file(change.path, table.concat(result, "\n"))
  vim.cmd("checktime")

  hunk_state.statuses[hunk_idx] = "rejected"
  vim.notify(string.format(" Hunk %d rejected", hunk_idx), vim.log.levels.WARN)

  place_extmarks()
end

local function accept_single_hunk(hunk_idx)
  hunk_state.statuses[hunk_idx] = "accepted"
  vim.notify(string.format(" Hunk %d accepted", hunk_idx), vim.log.levels.INFO)
  place_extmarks()
end

local function find_nearest_hunk()
  if not hunk_state.hunks or not hunk_state.buf then
    return nil
  end

  local cursor_row = vim.api.nvim_win_get_cursor(0)[1] -- 1-indexed
  local best_idx = nil
  local best_dist = math.huge

  for i, hunk in ipairs(hunk_state.hunks) do
    if not hunk_state.statuses[i] then
      local hunk_row = hunk.newStart or 1
      local dist = math.abs(cursor_row - hunk_row)
      if dist < best_dist then
        best_dist = dist
        best_idx = i
      end
    end
  end

  return best_idx
end

function M.show(session_id, file_path)
  if not session_id or not file_path then
    vim.notify("session_id and file_path are required", vim.log.levels.ERROR)
    return
  end

  local changes = index.get_changes(session_id)
  local target = nil
  for _, c in ipairs(changes) do
    if c.path == file_path then
      target = c
      break
    end
  end

  if not target then
    vim.notify("Change not found: " .. file_path, vim.log.levels.ERROR)
    return
  end

  if not target.patch or #target.patch == 0 then
    vim.notify("No hunks in this change", vim.log.levels.WARN)
    return
  end

  clear_state()
  hunk_state.change = target
  hunk_state.hunks = target.patch
  hunk_state.statuses = {}

  -- Open the file
  vim.cmd("tabnew " .. vim.fn.fnameescape(file_path))
  hunk_state.buf = vim.api.nvim_get_current_buf()

  -- Show original in vsplit
  vim.cmd("vsplit")
  hunk_state.orig_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(hunk_state.orig_buf)

  local orig_lines = {}
  if target.original then
    orig_lines = vim.split(target.original, "\n", { plain = true })
  end
  vim.api.nvim_buf_set_lines(hunk_state.orig_buf, 0, -1, false, orig_lines)
  vim.bo[hunk_state.orig_buf].buftype = "nofile"
  vim.bo[hunk_state.orig_buf].modifiable = false
  vim.api.nvim_buf_set_name(hunk_state.orig_buf, "claude://" .. file_path .. " (original)")

  local ft = vim.filetype.match({ filename = file_path })
  if ft then
    vim.bo[hunk_state.orig_buf].filetype = ft
  end

  vim.cmd("diffthis")
  vim.cmd("wincmd p")
  vim.cmd("diffthis")

  -- Place extmarks on the current file
  place_extmarks()

  local buf = hunk_state.buf

  -- a: accept nearest hunk
  vim.keymap.set("n", "a", function()
    local idx = find_nearest_hunk()
    if idx then
      accept_single_hunk(idx)
    end
  end, { buffer = buf, desc = "Accept hunk" })

  -- r: reject nearest hunk
  vim.keymap.set("n", "r", function()
    local idx = find_nearest_hunk()
    if idx then
      reject_single_hunk(idx)
    end
  end, { buffer = buf, desc = "Reject hunk" })

  -- ]h: next hunk
  vim.keymap.set("n", "]h", function()
    if not hunk_state.hunks then
      return
    end
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    for _, hunk in ipairs(hunk_state.hunks) do
      local hunk_row = hunk.newStart or 1
      if hunk_row > cursor_row then
        vim.api.nvim_win_set_cursor(0, { hunk_row, 0 })
        return
      end
    end
  end, { buffer = buf, desc = "次のhunk" })

  -- [h: prev hunk
  vim.keymap.set("n", "[h", function()
    if not hunk_state.hunks then
      return
    end
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    for i = #hunk_state.hunks, 1, -1 do
      local hunk_row = hunk_state.hunks[i].newStart or 1
      if hunk_row < cursor_row then
        vim.api.nvim_win_set_cursor(0, { hunk_row, 0 })
        return
      end
    end
  end, { buffer = buf, desc = "前のhunk" })

  -- q: close hunk view
  vim.keymap.set("n", "q", function()
    vim.cmd("tabclose")
    clear_state()
  end, { buffer = buf, desc = "閉じる" })
end

return M
