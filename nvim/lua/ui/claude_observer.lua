local observer_state = require("claude.observer_state")

local M = {}

local HORIZONTAL_PADDING = "    "
local VERTICAL_PADDING = 1

local state = {
  buf = nil,
  win = nil,
  tab = nil,
  subscription_id = nil,
  selected_session_id = nil,
  snapshot = nil,
  line_actions = {},
}

local function valid_buf(buf)
  return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
  return win and vim.api.nvim_win_is_valid(win)
end

local function valid_tab(tab)
  return tab and vim.api.nvim_tabpage_is_valid(tab)
end

local function state_hl(status)
  if status == "healthy" then
    return "DiagnosticOk"
  end
  if status == "degraded" then
    return "DiagnosticWarn"
  end
  if status == "blocked" or status == "failed" then
    return "DiagnosticError"
  end
  return "Comment"
end

local function coverage_hl(status)
  if status == "ok" then
    return "DiagnosticOk"
  end
  if status == "weak" then
    return "DiagnosticWarn"
  end
  return "DiagnosticError"
end

local function truncate_line(text, max_width)
  if max_width <= 0 then
    return ""
  end

  if vim.fn.strdisplaywidth(text) <= max_width then
    return text
  end

  local truncated = vim.fn.strcharpart(text, 0, math.max(1, max_width - 1))
  while vim.fn.strdisplaywidth(truncated .. "…") > max_width and vim.fn.strchars(truncated) > 1 do
    truncated = vim.fn.strcharpart(truncated, 0, vim.fn.strchars(truncated) - 1)
  end
  return truncated .. "…"
end

local function close_summary_window()
  local wins = vim.api.nvim_list_wins()
  for _, win in ipairs(wins) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "ClaudeObserverSummary" then
      vim.api.nvim_win_close(win, true)
    end
  end
end

local function reset_subscription()
  if state.subscription_id then
    observer_state.unsubscribe(state.subscription_id)
    state.subscription_id = nil
  end
end

local function reset_state()
  reset_subscription()
  state.buf = nil
  state.win = nil
  state.tab = nil
  state.snapshot = nil
  state.line_actions = {}
end

local function set_buffer_options(buf)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "ClaudeObserver"
end

local function panel_options(win)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true
  vim.wo[win].winfixwidth = true
end

local function current_opts()
  return {
    cwd = vim.fn.getcwd(),
    session_id = state.selected_session_id,
  }
end

local function session_index(snapshot)
  if not snapshot or not snapshot.selected_session_id then
    return nil, 0
  end

  for i, session in ipairs(snapshot.sessions) do
    if session.id == snapshot.selected_session_id then
      return i, #snapshot.sessions
    end
  end

  return nil, #snapshot.sessions
end

local function recent_sessions_line(snapshot)
  if not snapshot or #snapshot.sessions == 0 then
    return "recent: none"
  end

  local current_id = snapshot.selected_session_id
  local parts = {}
  for i = 1, math.min(3, #snapshot.sessions) do
    local session = snapshot.sessions[i]
    local prefix = session.id == current_id and "*" or " "
    parts[#parts + 1] = string.format(
      "%s%s %s",
      prefix,
      observer_state.format_clock(session.last_ts),
      session.summary
    )
  end

  return "recent: " .. table.concat(parts, " | ")
end

local function open_session_summary()
  local session = state.snapshot and state.snapshot.session
  if not session then
    vim.notify("No session available", vim.log.levels.WARN)
    return
  end

  close_summary_window()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "ClaudeObserverSummary"

  local lines = {
    "Session Summary",
    string.rep("─", 42),
    "id: " .. session.id,
    "updated: " .. observer_state.format_clock(session.last_ts),
    "messages: " .. tostring(session.msg_count or 0),
    "task: " .. (session.task or "n/a"),
    "summary: " .. (session.summary or "n/a"),
    "what changed: " .. (session.what_changed or "n/a"),
    "touched files: " .. tostring(session.touched_files_count or 0),
    "latest verify: " .. observer_state.describe_verification(session.latest_verification),
    "last good verify: " .. observer_state.format_clock(session.last_successful_verification_ts),
    "",
    "blockers:",
  }

  if session.blockers and #session.blockers > 0 then
    for _, blocker in ipairs(session.blockers) do
      lines[#lines + 1] = "  - " .. blocker
    end
  else
    lines[#lines + 1] = "  - none"
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "files:"
  if session.recent_files and #session.recent_files > 0 then
    for _, file in ipairs(session.recent_files) do
      lines[#lines + 1] = "  - " .. file
    end
  else
    lines[#lines + 1] = "  - none"
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "keys: q close  d diff  t timeline  R resume"

  vim.cmd("botright 52vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  panel_options(win)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local ns = vim.api.nvim_create_namespace("claude_observer_summary")
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
    end_row = 1,
    hl_group = "Title",
    hl_eol = true,
  })

  vim.keymap.set("n", "q", function()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end, { buffer = buf, desc = "Close summary" })

  vim.keymap.set("n", "d", function()
    if session.id then
      require("claude.diff").show(session.id)
    end
  end, { buffer = buf, desc = "Session diff" })

  vim.keymap.set("n", "t", function()
    if session.id then
      require("claude.timeline").show(session.id)
    end
  end, { buffer = buf, desc = "Session timeline" })

  vim.keymap.set("n", "R", function()
    if session.id then
      require("ui.claude_float").resume(session.id)
    end
  end, { buffer = buf, desc = "Resume session" })
end

local function run_action(index)
  local snapshot = state.snapshot
  if not snapshot or not snapshot.actions then
    return
  end

  local action = snapshot.actions[index]
  if not action then
    return
  end

  if not action.enabled then
    vim.notify(action.reason or "Action is unavailable", vim.log.levels.WARN)
    return
  end

  if action.kind == "open_summary" then
    open_session_summary()
    return
  end

  local ok, claude = pcall(require, "ui.claude_float")
  if not ok or type(claude.launch_prompt) ~= "function" then
    vim.notify("ui.claude_float.launch_prompt is unavailable", vim.log.levels.ERROR)
    return
  end

  claude.launch_prompt(action.prompt, {
    session_id = action.session_id,
    cwd = snapshot.cwd,
  })
end

local function render(snapshot)
  if not valid_buf(state.buf) then
    return
  end

  state.snapshot = snapshot
  state.selected_session_id = snapshot.selected_session_id
  state.line_actions = {}

  local lines = {}
  local line_hl = {}
  local ns = vim.api.nvim_create_namespace("claude_observer_panel")
  local content_width = 72
  if valid_win(state.win) then
    content_width = math.max(32, vim.api.nvim_win_get_width(state.win) - (#HORIZONTAL_PADDING * 2))
  end

  local function add(text, hl, action_index)
    local rendered = HORIZONTAL_PADDING .. truncate_line(text, content_width)
    lines[#lines + 1] = rendered
    if hl then
      line_hl[#lines] = hl
    end
    if action_index then
      state.line_actions[#lines] = action_index
    end
  end

  local index, total = session_index(snapshot)
  for _ = 1, VERTICAL_PADDING do
    add("")
  end

  add("AI Observer", "Title")
  add("repo: " .. vim.fn.fnamemodify(snapshot.cwd, ":t"), "Comment")
  if snapshot.selected_session_id then
    add(string.format("selected: [%d/%d] %s", index or 1, total, snapshot.selected_session_id), "Comment")
  else
    add("selected: none", "Comment")
  end
  add("keys: <CR> run  1-5 run  [s/]s switch  o summary  r refresh  q close", "Comment")
  add("")

  add("Current Health", "Title")
  add("state: " .. snapshot.health.state, state_hl(snapshot.health.state))
  add("task: " .. (snapshot.health.current_task or "n/a"))
  add("last good verify: " .. observer_state.format_clock(snapshot.health.last_successful_verification_ts))
  add("failing checks: " .. tostring(snapshot.health.failing_checks_count))
  add("blocked: " .. (snapshot.health.blocked and "yes" or "no"))
  add("active sessions: " .. tostring(snapshot.health.active_session_count))
  if snapshot.session and snapshot.health.state ~= "healthy" and snapshot.session.blockers[1] then
    add("issue: " .. snapshot.session.blockers[1], "DiagnosticError")
  end
  add("")

  add("Harness Coverage", "Title")
  for _, item in ipairs(snapshot.coverage) do
    add(string.format("%-8s %s", item.status, item.label), coverage_hl(item.status))
    if item.status ~= "ok" and item.detail then
      add("  " .. item.detail, "Comment")
    end
  end
  add("")

  add("Current / Selected Session", "Title")
  if snapshot.session then
    add(recent_sessions_line(snapshot), "Comment")
    add("task: " .. (snapshot.session.task or "n/a"))
    add("what changed: " .. (snapshot.session.what_changed or "n/a"))
    add("touched files: " .. tostring(snapshot.session.touched_files_count or 0))
    add("summary: " .. (snapshot.session.summary or "n/a"))
    add("blockers: " .. ((snapshot.session.blockers and snapshot.session.blockers[1]) or "none"))
    add("latest verify: " .. observer_state.describe_verification(snapshot.session.latest_verification))
  else
    add("No Claude session found for the current repository", "Comment")
  end
  add("")

  add("Actions", "Title")
  for i, action in ipairs(snapshot.actions) do
    local prefix = string.format("%d. ", i)
    local line = prefix .. action.label
    if not action.enabled and action.reason then
      line = line .. " [" .. action.reason .. "]"
    end
    add(line, action.enabled and "Identifier" or "Comment", i)
    if action.detail then
      add("  " .. action.detail, "Comment")
    end
  end

  for _ = 1, VERTICAL_PADDING do
    add("")
  end

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)

  for line_nr, hl in pairs(line_hl) do
    vim.api.nvim_buf_set_extmark(state.buf, ns, line_nr - 1, 0, {
      end_row = line_nr,
      hl_group = hl,
      hl_eol = true,
    })
  end

  vim.bo[state.buf].modifiable = false
end

local function refresh_subscription()
  if not valid_buf(state.buf) then
    return
  end

  if state.subscription_id then
    observer_state.update_subscription(state.subscription_id, current_opts())
    return
  end

  state.subscription_id = observer_state.subscribe(current_opts(), render)
end

local function next_session(direction)
  local snapshot = state.snapshot
  if not snapshot or #snapshot.sessions == 0 then
    return
  end

  local current_index = 1
  for i, session in ipairs(snapshot.sessions) do
    if session.id == snapshot.selected_session_id then
      current_index = i
      break
    end
  end

  local next_index = current_index + direction
  if next_index < 1 then
    next_index = #snapshot.sessions
  elseif next_index > #snapshot.sessions then
    next_index = 1
  end

  state.selected_session_id = snapshot.sessions[next_index].id
  refresh_subscription()
end

local function action_under_cursor()
  if not valid_win(state.win) then
    return nil
  end
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  return state.line_actions[row]
end

local function attach_keymaps(buf)
  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = buf, desc = "Close observer" })

  vim.keymap.set("n", "r", function()
    refresh_subscription()
  end, { buffer = buf, desc = "Refresh observer" })

  vim.keymap.set("n", "o", function()
    open_session_summary()
  end, { buffer = buf, desc = "Open summary" })

  vim.keymap.set("n", "<CR>", function()
    local index = action_under_cursor()
    if index then
      run_action(index)
    else
      open_session_summary()
    end
  end, { buffer = buf, desc = "Run action" })

  vim.keymap.set("n", "]s", function()
    next_session(1)
  end, { buffer = buf, desc = "Next session" })

  vim.keymap.set("n", "[s", function()
    next_session(-1)
  end, { buffer = buf, desc = "Previous session" })

  for i = 1, 5 do
    vim.keymap.set("n", tostring(i), function()
      run_action(i)
    end, { buffer = buf, desc = "Run observer action " .. i })
  end
end

local function ensure_buffer()
  if valid_buf(state.buf) then
    return state.buf
  end

  local buf = vim.api.nvim_create_buf(false, true)
  set_buffer_options(buf)
  attach_keymaps(buf)

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      close_summary_window()
      reset_state()
    end,
  })

  state.buf = buf
  return buf
end

function M.open()
  local buf = ensure_buffer()

  if valid_tab(state.tab) then
    vim.api.nvim_set_current_tabpage(state.tab)
    if valid_win(state.win) then
      vim.api.nvim_set_current_win(state.win)
    end
    refresh_subscription()
    return
  end

  vim.cmd("tabnew")
  state.tab = vim.api.nvim_get_current_tabpage()
  state.win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(state.win, buf)
  panel_options(state.win)

  refresh_subscription()
end

function M.close()
  close_summary_window()
  if valid_tab(state.tab) then
    vim.api.nvim_set_current_tabpage(state.tab)
    vim.cmd("tabclose")
  elseif valid_buf(state.buf) then
    vim.api.nvim_buf_delete(state.buf, { force = true })
  end
  reset_state()
end

function M.toggle()
  if valid_win(state.win) then
    M.close()
    return
  end
  M.open()
end

function M.refresh()
  refresh_subscription()
end

return M
