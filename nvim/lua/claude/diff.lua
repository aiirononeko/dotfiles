local index = require("claude.session_index")

local M = {}

local list_buf = nil
local list_win = nil
local current_changes = nil

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local content = fd:read("*a")
  fd:close()
  return content
end

local function split_lines(text)
  if type(text) ~= "string" or text == "" then
    return {}
  end

  local lines = vim.split(text, "\n", { plain = true, trimempty = false })
  if lines[#lines] == "" then
    table.remove(lines, #lines)
  end
  return lines
end

local function is_diff_preview_name(name)
  return type(name) == "string" and name:sub(1, #"claude://diff/") == "claude://diff/"
end

local function is_diff_preview_buf(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  return vim.bo[buf].buftype == "nofile" and is_diff_preview_name(vim.api.nvim_buf_get_name(buf))
end

local function close_list()
  if list_win and vim.api.nvim_win_is_valid(list_win) then
    vim.api.nvim_win_close(list_win, true)
  end
  if list_buf and vim.api.nvim_buf_is_valid(list_buf) then
    vim.api.nvim_buf_delete(list_buf, { force = true })
  end
  list_buf = nil
  list_win = nil
  current_changes = nil
end

local function build_hunk_header(hunk)
  local old_start = tonumber(hunk.oldStart) or 0
  local old_lines = tonumber(hunk.oldLines) or 0
  local new_start = tonumber(hunk.newStart) or 0
  local new_lines = tonumber(hunk.newLines) or 0

  return string.format("@@ -%d,%d +%d,%d @@", old_start, old_lines, new_start, new_lines)
end

local function append_patch_lines(lines, patch)
  local hunks = patch and (patch.hunks or patch) or nil
  if type(hunks) ~= "table" or next(hunks) == nil then
    return false
  end

  for _, hunk in ipairs(hunks) do
    lines[#lines + 1] = build_hunk_header(hunk)
    for _, hunk_line in ipairs(hunk.lines or {}) do
      lines[#lines + 1] = hunk_line
    end
  end
  return true
end

local function build_unified_lines(change)
  local lines = {}

  if change.user_modified == true then
    lines[#lines + 1] = "⚠ ユーザーによる追加変更あり"
  end

  lines[#lines + 1] = "--- a/" .. change.path
  lines[#lines + 1] = "+++ b/" .. change.path

  if append_patch_lines(lines, change.patch) then
    return lines
  end

  if change.kind == "create" and type(change.content) == "string" then
    local content_lines = split_lines(change.content)
    if #content_lines > 0 then
      lines[#lines + 1] = string.format("@@ -0,0 +1,%d @@", #content_lines)
      for _, content_line in ipairs(content_lines) do
        lines[#lines + 1] = "+" .. content_line
      end
    end
    return lines
  end

  if type(change.original) == "string" then
    local current = read_file(change.path) or ""
    local diff = vim.diff(change.original, current, { result_type = "unified" })
    for _, diff_line in ipairs(split_lines(diff)) do
      lines[#lines + 1] = diff_line
    end
    return lines
  end

  lines[#lines + 1] = "(diff unavailable)"
  return lines
end

local function is_target_win(win, source_win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  if source_win and win == source_win then
    return false
  end

  local config = vim.api.nvim_win_get_config(win)
  if config.relative ~= "" then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return false
  end

  local filetype = vim.bo[buf].filetype or ""
  if filetype:match("^neo%-tree") then
    return false
  end

  local buftype = vim.bo[buf].buftype or ""
  return buftype == "" or buftype == "nofile"
end

local function find_target_win(source_win)
  local base_win = source_win
  if not (base_win and vim.api.nvim_win_is_valid(base_win)) then
    base_win = vim.api.nvim_get_current_win()
  end
  local tabpage = vim.api.nvim_win_get_tabpage(base_win)
  local wins = vim.api.nvim_tabpage_list_wins(tabpage)
  local base_pos = vim.api.nvim_win_get_position(base_win)
  local candidates = {}

  for _, win in ipairs(wins) do
    if is_target_win(win, source_win) then
      candidates[#candidates + 1] = win
    end
  end

  -- 既存のdiffプレビューバッファを優先、次にsource_winの右側を優先
  table.sort(candidates, function(a, b)
    local a_preview = is_diff_preview_buf(vim.api.nvim_win_get_buf(a))
    local b_preview = is_diff_preview_buf(vim.api.nvim_win_get_buf(b))
    if a_preview ~= b_preview then
      return a_preview
    end
    local a_pos = vim.api.nvim_win_get_position(a)
    local b_pos = vim.api.nvim_win_get_position(b)
    local a_right = a_pos[2] > base_pos[2]
    local b_right = b_pos[2] > base_pos[2]
    if a_right ~= b_right then
      return a_right
    end
    return a_pos[2] < b_pos[2]
  end)

  if #candidates > 0 then
    return candidates[1]
  end

  vim.api.nvim_set_current_win(base_win)
  vim.cmd("rightbelow vsplit")
  return vim.api.nvim_get_current_win()
end

local function get_or_create_preview_buf(target_win, buf_name)
  local named = vim.fn.bufnr(buf_name)
  if named > 0 and vim.api.nvim_buf_is_valid(named) and vim.bo[named].buftype == "nofile" then
    return named
  end

  local win_buf = vim.api.nvim_win_get_buf(target_win)
  if is_diff_preview_buf(win_buf) then
    return win_buf
  end

  return vim.api.nvim_create_buf(false, true)
end

local function set_preview_keymaps(buf, change, opts)
  vim.keymap.set("n", "q", function()
    vim.cmd("bwipeout")
  end, { buffer = buf, desc = "Diff を閉じる" })

  vim.keymap.set("n", "o", function()
    vim.cmd("edit " .. vim.fn.fnameescape(change.path))
  end, { buffer = buf, desc = "実ファイルを開く" })

  vim.keymap.set("n", "a", function()
    local session_id = opts.session_id
    if type(session_id) ~= "string" or session_id == "" then
      vim.notify("session_id is required", vim.log.levels.ERROR)
      return
    end

    local ok, accept_reject_hunk = pcall(require, "claude.accept_reject_hunk")
    if not ok then
      vim.notify("claude.accept_reject_hunk could not be loaded", vim.log.levels.ERROR)
      return
    end

    accept_reject_hunk.show(session_id, change.path)
  end, { buffer = buf, desc = "Hunk 単位で Accept/Reject" })
end

function M.show_change(change, opts)
  opts = opts or {}

  if type(change) ~= "table" or type(change.path) ~= "string" or change.path == "" then
    vim.notify("change.path is required", vim.log.levels.ERROR)
    return
  end

  local source_win = opts.source_win
  if source_win and not vim.api.nvim_win_is_valid(source_win) then
    source_win = nil
  end

  local lines = build_unified_lines(change)
  local target_win = find_target_win(source_win)
  local buf_name = "claude://diff/" .. change.path
  local preview_buf = get_or_create_preview_buf(target_win, buf_name)

  vim.api.nvim_set_current_win(target_win)
  vim.api.nvim_win_set_buf(target_win, preview_buf)

  vim.bo[preview_buf].buftype = "nofile"
  vim.bo[preview_buf].bufhidden = "wipe"
  vim.bo[preview_buf].swapfile = false
  vim.bo[preview_buf].buflisted = false
  vim.bo[preview_buf].modifiable = true
  vim.bo[preview_buf].readonly = false
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, lines)
  vim.bo[preview_buf].modifiable = false
  vim.bo[preview_buf].readonly = true
  vim.bo[preview_buf].filetype = "diff"
  vim.api.nvim_buf_set_name(preview_buf, buf_name)
  vim.api.nvim_win_set_cursor(target_win, { 1, 0 })

  set_preview_keymaps(preview_buf, change, opts)

  if opts.focus ~= true and source_win and vim.api.nvim_win_is_valid(source_win) then
    vim.api.nvim_set_current_win(source_win)
  end
end

M.find_target_win = find_target_win

local function open_diff(change, session_id)
  M.show_change(change, {
    source_win = list_win,
    focus = false,
    session_id = session_id,
  })
end

local function refresh_list(session_id)
  local changes = index.get_changes(session_id)
  current_changes = changes

  if not list_buf or not vim.api.nvim_buf_is_valid(list_buf) then
    return
  end

  local lines = {}
  for _, c in ipairs(changes) do
    local icon = c.kind == "create" and "[+]" or "[~]"
    lines[#lines + 1] = string.format(" %s %s", icon, c.path)
  end

  if #lines == 0 then
    lines = { "  (no file changes)" }
  end

  vim.bo[list_buf].modifiable = true
  vim.api.nvim_buf_set_lines(list_buf, 0, -1, false, lines)
  vim.bo[list_buf].modifiable = false
end

function M.show(session_id)
  if not session_id or session_id == "" then
    vim.notify("session_id is required", vim.log.levels.ERROR)
    return
  end

  close_list()

  list_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[list_buf].buftype = "nofile"
  vim.bo[list_buf].filetype = "ClaudeDiffList"
  vim.bo[list_buf].bufhidden = "wipe"

  vim.cmd("topleft 35vsplit")
  list_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(list_win, list_buf)
  vim.wo[list_win].number = false
  vim.wo[list_win].relativenumber = false
  vim.wo[list_win].signcolumn = "no"
  vim.wo[list_win].winfixwidth = true

  refresh_list(session_id)

  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    if current_changes and current_changes[row] then
      open_diff(current_changes[row], session_id)
    end
  end, { buffer = list_buf, desc = "Diff を表示" })

  vim.keymap.set("n", "q", function()
    close_list()
  end, { buffer = list_buf, desc = "閉じる" })

  vim.keymap.set("n", "r", function()
    refresh_list(session_id)
  end, { buffer = list_buf, desc = "リフレッシュ" })
end

return M
