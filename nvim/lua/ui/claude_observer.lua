local observer_state = require("claude.observer_state")

local M = {}

local HORIZONTAL_PADDING = "  "
local VERTICAL_PADDING = 1
local PANEL_NS = vim.api.nvim_create_namespace("claude_observer_panel")
local SUMMARY_NS = vim.api.nvim_create_namespace("claude_observer_summary")

local PALETTE = {
  bg = "#16161e",
  bg_alt = "#1f2335",
  fg = "#c0caf5",
  muted = "#565f89",
  blue = "#7aa2f7",
  cyan = "#7dcfff",
  green = "#9ece6a",
  yellow = "#e0af68",
  orange = "#ff9e64",
  red = "#f7768e",
  magenta = "#bb9af7",
}

local highlights_ready = false

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

local function setup_highlights()
  if highlights_ready then
    return
  end

  vim.api.nvim_set_hl(0, "ClaudeObserverHeader", { fg = PALETTE.blue, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverSubtle", { fg = PALETTE.muted })
  vim.api.nvim_set_hl(0, "ClaudeObserverCard", { fg = PALETTE.fg, bg = PALETTE.bg })
  vim.api.nvim_set_hl(0, "ClaudeObserverCardBorder", { fg = PALETTE.muted, bg = PALETTE.bg })
  vim.api.nvim_set_hl(0, "ClaudeObserverAccent", { fg = PALETTE.cyan, bg = PALETTE.bg, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverHealthy", { fg = PALETTE.bg, bg = PALETTE.green, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverIdle", { fg = PALETTE.bg, bg = PALETTE.blue, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverDegraded", { fg = PALETTE.bg, bg = PALETTE.yellow, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverBlocked", { fg = PALETTE.bg, bg = PALETTE.orange, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverFailed", { fg = PALETTE.bg, bg = PALETTE.red, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverCoverageOk", { fg = PALETTE.green, bg = PALETTE.bg, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverCoverageWeak", { fg = PALETTE.yellow, bg = PALETTE.bg, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverCoverageMissing", { fg = PALETTE.red, bg = PALETTE.bg, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverAction", { fg = PALETTE.blue, bg = PALETTE.bg_alt, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverPrimaryAction", { fg = PALETTE.bg, bg = PALETTE.cyan, bold = true })
  vim.api.nvim_set_hl(0, "ClaudeObserverActionMuted", { fg = PALETTE.muted, bg = PALETTE.bg })

  highlights_ready = true
end

local function state_hl(status)
  if status == "healthy" then
    return "ClaudeObserverHealthy"
  end
  if status == "idle" then
    return "ClaudeObserverIdle"
  end
  if status == "degraded" then
    return "ClaudeObserverDegraded"
  end
  if status == "blocked" then
    return "ClaudeObserverBlocked"
  end
  if status == "failed" then
    return "ClaudeObserverFailed"
  end
  return "ClaudeObserverSubtle"
end

local function coverage_hl(status)
  if status == "ok" then
    return "ClaudeObserverCoverageOk"
  end
  if status == "weak" then
    return "ClaudeObserverCoverageWeak"
  end
  return "ClaudeObserverCoverageMissing"
end

local function display_width(text)
  return vim.fn.strdisplaywidth(text or "")
end

local function truncate_line(text, max_width)
  if max_width <= 0 then
    return ""
  end

  text = text or ""
  if display_width(text) <= max_width then
    return text
  end

  local truncated = vim.fn.strcharpart(text, 0, math.max(1, max_width - 1))
  while display_width(truncated .. "…") > max_width and vim.fn.strchars(truncated) > 1 do
    truncated = vim.fn.strcharpart(truncated, 0, vim.fn.strchars(truncated) - 1)
  end
  return truncated .. "…"
end

local function pad_line(text, width)
  local rendered = truncate_line(text or "", width)
  local gap = width - display_width(rendered)
  if gap > 0 then
    rendered = rendered .. string.rep(" ", gap)
  end
  return rendered
end

local function box_top(title, width)
  local label = " " .. truncate_line(title or "", math.max(1, width - 4)) .. " "
  local fill = math.max(0, width - 2 - display_width(label))
  return "╭" .. label .. string.rep("─", fill) .. "╮"
end

local function box_divider(width)
  return "├" .. string.rep("─", math.max(0, width - 2)) .. "┤"
end

local function box_body(text, width)
  return "│ " .. pad_line(text or "", math.max(1, width - 4)) .. " │"
end

local function box_bottom(width)
  return "╰" .. string.rep("─", math.max(0, width - 2)) .. "╯"
end

local function new_row(text, opts)
  opts = opts or {}
  return {
    text = text or "",
    hl = opts.hl,
    action_index = opts.action_index,
    divider = opts.divider,
    ranges = opts.ranges,
  }
end

local function blank_entry()
  return new_row("")
end

local function append_entries(target, entries)
  for _, entry in ipairs(entries) do
    target[#target + 1] = entry
  end
end

local function empty_segment(width)
  return new_row(string.rep(" ", math.max(0, width)))
end

local function card_rows(title, body_rows, width, opts)
  opts = opts or {}
  local border_hl = opts.border_hl or "ClaudeObserverCardBorder"
  local body_hl = opts.body_hl or "ClaudeObserverCard"
  local rows = {
    new_row(box_top(title, width), { hl = border_hl }),
  }

  if #body_rows == 0 then
    body_rows = { new_row("No data", { hl = "ClaudeObserverSubtle" }) }
  end

  for _, row in ipairs(body_rows) do
    if row.divider then
      rows[#rows + 1] = new_row(box_divider(width), { hl = border_hl })
    else
      rows[#rows + 1] = new_row(box_body(row.text, width), {
        hl = row.hl or body_hl,
        action_index = row.action_index,
      })
    end
  end

  rows[#rows + 1] = new_row(box_bottom(width), { hl = border_hl })
  return rows
end

local function merge_blocks(left_rows, left_width, right_rows, right_width, gap)
  local merged = {}
  local gap_text = string.rep(" ", gap)
  local total = math.max(#left_rows, #right_rows)

  for i = 1, total do
    local left = left_rows[i] or empty_segment(left_width)
    local right = right_rows[i] or empty_segment(right_width)
    local text = left.text .. gap_text .. right.text
    local ranges = {}

    if left.hl then
      ranges[#ranges + 1] = { start_col = 0, end_col = #left.text, hl = left.hl }
    end
    if right.hl then
      local start_col = #left.text + #gap_text
      ranges[#ranges + 1] = { start_col = start_col, end_col = start_col + #right.text, hl = right.hl }
    end

    merged[#merged + 1] = new_row(text, { ranges = ranges })
  end

  return merged
end

local function count_items(items, status)
  local count = 0
  for _, item in ipairs(items or {}) do
    if item.status == status then
      count = count + 1
    end
  end
  return count
end

local function state_meter(status)
  local value_map = {
    healthy = 5,
    idle = 4,
    degraded = 3,
    blocked = 2,
    failed = 1,
  }
  local score = value_map[status] or 0
  local blocks = {}
  for i = 1, 5 do
    blocks[#blocks + 1] = i <= score and "█" or "░"
  end
  return table.concat(blocks, "")
end

local function short_session_id(session_id)
  if not session_id or session_id == "" then
    return "none"
  end
  if #session_id <= 16 then
    return session_id
  end
  return session_id:sub(1, 7) .. "…" .. session_id:sub(-6)
end

local function current_selection_line(snapshot)
  local total = #snapshot.sessions
  if total == 0 or not snapshot.selected_session_id then
    return "selected: none"
  end

  local index = 1
  for i, session in ipairs(snapshot.sessions) do
    if session.id == snapshot.selected_session_id then
      index = i
      break
    end
  end

  return string.format("selected: %d/%d  %s", index, total, short_session_id(snapshot.selected_session_id))
end

local function top_coverage_gap(snapshot)
  for _, item in ipairs(snapshot.coverage or {}) do
    if item.status ~= "ok" then
      return item
    end
  end
  return nil
end

local function health_rows(snapshot)
  local health = snapshot.health
  local required_gap = string.format("%d missing / %d weak", health.required_missing_count or 0, health.required_weak_count or 0)
  local rows = {
    new_row(string.format("STATE        %s  %s", string.upper(health.state or "idle"), state_meter(health.state)), {
      hl = state_hl(health.state),
    }),
    new_row("ACTIVITY     " .. (health.activity or "observer idle")),
    new_row("SESSIONS     " .. tostring(health.active_session_count or 0) .. " active"),
    new_row("CHECKS       " .. tostring(health.failing_checks_count or 0) .. " failing"),
    new_row("LAST GOOD    " .. observer_state.format_clock(health.last_successful_verification_ts)),
    new_row("STUCK        " .. ((health.blocked_session_count or 0) > 0 and (tostring(health.blocked_session_count) .. " session") or "none"), {
      hl = (health.blocked_session_count or 0) > 0 and "ClaudeObserverCoverageMissing" or "ClaudeObserverSubtle",
    }),
    new_row("HARNESS      " .. required_gap, {
      hl = (health.required_missing_count or 0) > 0 and "ClaudeObserverCoverageMissing"
        or (health.required_weak_count or 0) > 0 and "ClaudeObserverCoverageWeak"
        or "ClaudeObserverCoverageOk",
    }),
    new_row("NEXT         " .. (health.next_step or "No intervention needed"), {
      hl = health.state == "healthy" and "ClaudeObserverSubtle" or "ClaudeObserverAction",
    }),
  }

  return rows
end

local function focus_rows(snapshot)
  local session = snapshot.session
  if not session then
    return {
      new_row("No Claude session found for this repository.", { hl = "ClaudeObserverSubtle" }),
      new_row("Open Claude Code in the repo to populate the observer.", { hl = "ClaudeObserverSubtle" }),
    }
  end

  local rows = {
    new_row(
      "SESSION      " .. short_session_id(session.id) .. "  @ " .. observer_state.format_clock(session.last_ts),
      { hl = "ClaudeObserverAccent" }
    ),
    new_row("GOAL         " .. (session.goal or session.task or "n/a")),
    new_row("LAST ACTION  " .. (session.last_action or "none recorded")),
    new_row("SCOPE        " .. (session.what_changed or "n/a")),
    new_row("SUMMARY      " .. (session.summary_line or session.summary or "n/a")),
    new_row("BLOCKER      " .. (session.current_blocker or "none"), {
      hl = session.current_blocker and "ClaudeObserverCoverageMissing" or "ClaudeObserverCoverageOk",
    }),
    new_row("VERIFY       " .. observer_state.describe_verification(session.latest_verification)),
  }

  if session.pending_tools and session.pending_tools[1] then
    rows[#rows + 1] = new_row("RUNNING      " .. (session.pending_tools[1].summary or "in progress"), {
      hl = "ClaudeObserverCoverageWeak",
    })
  end

  return rows
end

local function coverage_rows(snapshot)
  local rows = {
    new_row(string.format(
      "SUMMARY      %d ok   %d weak   %d missing",
      count_items(snapshot.coverage, "ok"),
      count_items(snapshot.coverage, "weak"),
      count_items(snapshot.coverage, "missing")
    ), { hl = "ClaudeObserverAccent" }),
    new_row("", { divider = true }),
  }

  for _, item in ipairs(snapshot.coverage) do
    local detail = item.status == "ok" and "" or ("  " .. (item.detail or ""))
    rows[#rows + 1] = new_row(string.format(
      "%-7s  %-11s  %s%s",
      string.upper(item.status),
      string.upper(item.priority or "recommended"),
      item.label,
      detail
    ), {
      hl = coverage_hl(item.status),
    })
  end

  return rows
end

local function signals_rows(snapshot)
  local session = snapshot.session
  local coverage_gap = top_coverage_gap(snapshot)
  local rows = {}

  if session and session.latest_anomaly then
    rows[#rows + 1] = new_row("ANOMALY      " .. session.latest_anomaly, { hl = "ClaudeObserverCoverageMissing" })
  else
    rows[#rows + 1] = new_row("ANOMALY      none recorded", { hl = "ClaudeObserverSubtle" })
  end

  if session and session.last_state_transition then
    rows[#rows + 1] = new_row("TRANSITION   " .. session.last_state_transition, {
      hl = snapshot.health.state == "healthy" and "ClaudeObserverCoverageOk" or "ClaudeObserverCoverageWeak",
    })
  else
    rows[#rows + 1] = new_row("TRANSITION   observer idle", { hl = "ClaudeObserverSubtle" })
  end

  if session and session.recent_files and #session.recent_files > 0 then
    rows[#rows + 1] = new_row("FILES        " .. table.concat(session.recent_files, ", "))
  else
    rows[#rows + 1] = new_row("FILES        none", { hl = "ClaudeObserverSubtle" })
  end

  if session and session.current_risk then
    rows[#rows + 1] = new_row("RISK         " .. session.current_risk, {
      hl = session.current_blocker and "ClaudeObserverCoverageMissing" or "ClaudeObserverCoverageWeak",
    })
  elseif coverage_gap then
    rows[#rows + 1] = new_row("RISK         " .. coverage_gap.label .. " is " .. coverage_gap.status, {
      hl = coverage_hl(coverage_gap.status),
    })
  else
    rows[#rows + 1] = new_row("RISK         no active risk", { hl = "ClaudeObserverCoverageOk" })
  end

  return rows
end

local function actions_rows(snapshot)
  local rows = {
    new_row("Primary action first. `<CR>` or `1-5` launches Claude Code. `o` opens session detail.", {
      hl = "ClaudeObserverSubtle",
    }),
    new_row("", { divider = true }),
  }

  for i, action in ipairs(snapshot.actions) do
    local label = action.primary and string.format("[%d] PRIMARY  %s", i, action.label) or string.format("[%d] %s", i, action.label)
    if not action.enabled and action.reason then
      label = label .. "  (" .. action.reason .. ")"
    end

    rows[#rows + 1] = new_row(label, {
      hl = action.enabled and (action.primary and "ClaudeObserverPrimaryAction" or "ClaudeObserverAction")
        or "ClaudeObserverActionMuted",
      action_index = i,
    })

    if action.detail then
      rows[#rows + 1] = new_row("    " .. action.detail, { hl = "ClaudeObserverSubtle" })
    end
  end

  return rows
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

local function render_entries(buf, ns, entries, line_actions)
  local lines = {}
  local line_hl = {}
  local ranges = {}
  local padding_bytes = #HORIZONTAL_PADDING

  for i, entry in ipairs(entries) do
    local text = HORIZONTAL_PADDING .. entry.text
    lines[i] = text

    if entry.hl then
      line_hl[i] = entry.hl
    end

    if entry.action_index then
      line_actions[i] = entry.action_index
    end

    if entry.ranges and #entry.ranges > 0 then
      ranges[i] = {}
      for _, range in ipairs(entry.ranges) do
        ranges[i][#ranges[i] + 1] = {
          start_col = range.start_col + padding_bytes,
          end_col = range.end_col + padding_bytes,
          hl = range.hl,
        }
      end
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for line_nr, hl in pairs(line_hl) do
    vim.api.nvim_buf_set_extmark(buf, ns, line_nr - 1, 0, {
      end_row = line_nr,
      hl_group = hl,
      hl_eol = true,
    })
  end

  for line_nr, line_ranges in pairs(ranges) do
    for _, range in ipairs(line_ranges) do
      vim.api.nvim_buf_add_highlight(buf, ns, range.hl, line_nr - 1, range.start_col, range.end_col)
    end
  end

  vim.bo[buf].modifiable = false
end

local function open_session_summary()
  local session = state.snapshot and state.snapshot.session
  if not session then
    vim.notify("No session available", vim.log.levels.WARN)
    return
  end

  close_summary_window()
  setup_highlights()

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "ClaudeObserverSummary"

  vim.cmd("botright 60vsplit")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  panel_options(win)

  local content_width = math.max(42, vim.api.nvim_win_get_width(win) - (#HORIZONTAL_PADDING * 2))
  local entries = {}
  local blockers = {}
  local files = {}

  for _ = 1, VERTICAL_PADDING do
    entries[#entries + 1] = blank_entry()
  end

  entries[#entries + 1] = new_row("Session Deep Dive", { hl = "ClaudeObserverHeader" })
  entries[#entries + 1] = new_row(short_session_id(session.id) .. "  •  updated " .. observer_state.format_clock(session.last_ts), {
    hl = "ClaudeObserverSubtle",
  })
  entries[#entries + 1] = blank_entry()

  append_entries(entries, card_rows("Overview", {
    new_row("SESSION      " .. short_session_id(session.id), { hl = "ClaudeObserverAccent" }),
    new_row("UPDATED      " .. observer_state.format_clock(session.last_ts)),
    new_row("MESSAGES     " .. tostring(session.msg_count or 0)),
    new_row("GOAL         " .. (session.goal or session.task or "n/a")),
    new_row("LAST ACTION  " .. (session.last_action or "none recorded")),
    new_row("SUMMARY      " .. (session.summary_line or session.summary or "n/a")),
    new_row("SCOPE        " .. (session.what_changed or "n/a")),
  }, content_width))

  entries[#entries + 1] = blank_entry()

  append_entries(entries, card_rows("Verification", {
    new_row("LATEST       " .. observer_state.describe_verification(session.latest_verification), {
      hl = session.latest_verification and coverage_hl(session.latest_verification.status == "ok" and "ok" or "missing")
        or "ClaudeObserverSubtle",
    }),
    new_row("LAST GOOD    " .. observer_state.format_clock(session.last_successful_verification_ts)),
    new_row("FAILURES     " .. tostring(session.failing_checks_count or 0)),
    new_row("TRANSITION   " .. (session.last_state_transition or "none recorded")),
    new_row(
      "RUNNING      " .. ((session.pending_tools and session.pending_tools[1] and session.pending_tools[1].summary) or "none"),
      { hl = session.pending_tools and session.pending_tools[1] and "ClaudeObserverCoverageWeak" or "ClaudeObserverSubtle" }
    ),
  }, content_width))

  entries[#entries + 1] = blank_entry()

  if session.blockers and #session.blockers > 0 then
    for _, blocker in ipairs(session.blockers) do
      blockers[#blockers + 1] = new_row("• " .. blocker, { hl = "ClaudeObserverCoverageMissing" })
    end
  else
    blockers[1] = new_row("No active blockers", { hl = "ClaudeObserverCoverageOk" })
  end

  append_entries(entries, card_rows("Blockers", blockers, content_width))

  entries[#entries + 1] = blank_entry()

  if session.recent_files and #session.recent_files > 0 then
    for _, file in ipairs(session.recent_files) do
      files[#files + 1] = new_row("• " .. file)
    end
  else
    files[1] = new_row("No recent file edits recorded", { hl = "ClaudeObserverSubtle" })
  end

  append_entries(entries, card_rows("Touched Files", files, content_width))

  entries[#entries + 1] = blank_entry()

  append_entries(entries, card_rows("Keys", {
    new_row("q close   d diff   t timeline   R resume", { hl = "ClaudeObserverSubtle" }),
  }, content_width))

  for _ = 1, VERTICAL_PADDING do
    entries[#entries + 1] = blank_entry()
  end

  render_entries(buf, SUMMARY_NS, entries, {})

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

  setup_highlights()

  state.snapshot = snapshot
  state.selected_session_id = snapshot.selected_session_id
  state.line_actions = {}

  local entries = {}
  local content_width = 72
  if valid_win(state.win) then
    content_width = math.max(40, vim.api.nvim_win_get_width(state.win) - (#HORIZONTAL_PADDING * 2))
  end

  local title_line = string.format(
    "%s  %s  •  %s",
    "AI Observer",
    vim.fn.fnamemodify(snapshot.cwd, ":t"),
    current_selection_line(snapshot)
  )
  local status_line = string.format(
    "%s  failing %d  •  blocked %s  •  active %d",
    string.upper(snapshot.health.state or "idle"),
    snapshot.health.failing_checks_count or 0,
    snapshot.health.blocked and "yes" or "no",
    snapshot.health.active_session_count or 0
  )

  for _ = 1, VERTICAL_PADDING do
    entries[#entries + 1] = blank_entry()
  end

  entries[#entries + 1] = new_row(truncate_line(title_line, content_width), { hl = "ClaudeObserverHeader" })
  entries[#entries + 1] = new_row(truncate_line(status_line .. "  " .. state_meter(snapshot.health.state), content_width), {
    hl = state_hl(snapshot.health.state),
  })
  entries[#entries + 1] = new_row(
    truncate_line("keys: <CR> run  1-5 run  [s/]s switch  o summary  r refresh  q close", content_width),
    { hl = "ClaudeObserverSubtle" }
  )
  entries[#entries + 1] = blank_entry()

  local two_column = content_width >= 112
  local gap = 4
  local half_width = two_column and math.floor((content_width - gap) / 2) or content_width
  local remainder_width = two_column and (content_width - gap - half_width) or content_width

  local health_block = card_rows("Current Health", health_rows(snapshot), half_width)
  local focus_block = card_rows("Selected Session", focus_rows(snapshot), remainder_width)
  local coverage_block = card_rows("Harness Coverage", coverage_rows(snapshot), half_width)
  local signals_block = card_rows("Recent Evidence", signals_rows(snapshot), remainder_width)
  local actions_block = card_rows("Recommended Actions", actions_rows(snapshot), content_width)

  if two_column then
    append_entries(entries, merge_blocks(health_block, half_width, focus_block, remainder_width, gap))
    entries[#entries + 1] = blank_entry()
    append_entries(entries, actions_block)
    entries[#entries + 1] = blank_entry()
    append_entries(entries, merge_blocks(coverage_block, half_width, signals_block, remainder_width, gap))
  else
    append_entries(entries, health_block)
    entries[#entries + 1] = blank_entry()
    append_entries(entries, focus_block)
    entries[#entries + 1] = blank_entry()
    append_entries(entries, actions_block)
    entries[#entries + 1] = blank_entry()
    append_entries(entries, coverage_block)
    entries[#entries + 1] = blank_entry()
    append_entries(entries, signals_block)
  end

  for _ = 1, VERTICAL_PADDING do
    entries[#entries + 1] = blank_entry()
  end

  render_entries(state.buf, PANEL_NS, entries, state.line_actions)
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
  setup_highlights()

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
