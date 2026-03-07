local index = require("claude.session_index")

local M = {}

local list_buf = nil
local list_win = nil
local current_changes = nil

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

local function detect_filetype(path)
  local ft = vim.filetype.match({ filename = path })
  return ft or ""
end

local function open_diff(change)
  local orig_lines = {}
  if change.original then
    orig_lines = vim.split(change.original, "\n", { plain = true })
  end

  vim.cmd("tabnew")

  -- Right: current file or empty
  local right_path = change.path
  local file_exists = vim.uv.fs_stat(right_path)
  if file_exists then
    vim.cmd("edit " .. vim.fn.fnameescape(right_path))
  else
    local right_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(right_buf)
    vim.bo[right_buf].buftype = "nofile"
    vim.api.nvim_buf_set_name(right_buf, "claude://" .. right_path .. " (current)")
  end
  vim.cmd("diffthis")

  -- Left: original content (scratch)
  vim.cmd("vsplit")
  local orig_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(orig_buf)
  vim.api.nvim_buf_set_lines(orig_buf, 0, -1, false, orig_lines)
  vim.bo[orig_buf].buftype = "nofile"
  vim.bo[orig_buf].modifiable = false
  vim.api.nvim_buf_set_name(orig_buf, "claude://" .. change.path .. " (original)")

  local ft = detect_filetype(change.path)
  if ft ~= "" then
    vim.bo[orig_buf].filetype = ft
  end

  vim.cmd("diffthis")

  -- q to close diff tab
  vim.keymap.set("n", "q", function()
    vim.cmd("tabclose")
  end, { buffer = orig_buf, desc = "Diff を閉じる" })
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

  -- Keymaps
  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    if current_changes and current_changes[row] then
      open_diff(current_changes[row])
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
