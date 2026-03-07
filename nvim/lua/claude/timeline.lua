local index = require("claude.session_index")

local M = {}

local timeline_buf = nil
local timeline_win = nil
local timeline_events = nil

local json_decode = vim.json and vim.json.decode or vim.fn.json_decode

local TOOL_ICONS = {
  Read = "  ",
  Write = "  ",
  Edit = "  ",
  Bash = "  ",
  Glob = "  ",
  Grep = "  ",
  Agent = "  ",
  WebFetch = "  ",
  WebSearch = "  ",
}

local TOOL_HL = {
  Read = "Comment",
  Write = "DiagnosticOk",
  Edit = "DiagnosticWarn",
  Bash = "DiagnosticInfo",
  Glob = "Comment",
  Grep = "Comment",
  Agent = "DiagnosticHint",
  WebFetch = "DiagnosticInfo",
  WebSearch = "DiagnosticInfo",
}

local function extract_summary(block)
  local name = block.name or ""
  local input = block.input or {}

  if name == "Read" then
    return vim.fn.fnamemodify(input.file_path or "", ":t")
  elseif name == "Write" then
    return vim.fn.fnamemodify(input.file_path or "", ":t")
  elseif name == "Edit" then
    return vim.fn.fnamemodify(input.file_path or "", ":t")
  elseif name == "Bash" then
    local cmd = input.command or ""
    if #cmd > 40 then
      cmd = cmd:sub(1, 40) .. "..."
    end
    return cmd
  elseif name == "Glob" or name == "Grep" then
    return input.pattern or input.query or ""
  else
    return name
  end
end

local function parse_time(ts_value)
  if type(ts_value) == "number" then
    local sec = ts_value > 1000000000000 and math.floor(ts_value / 1000) or ts_value
    return os.date("%H:%M", sec)
  end
  if type(ts_value) == "string" then
    local h, m = ts_value:match("(%d%d):(%d%d)")
    if h then
      return h .. ":" .. m
    end
  end
  return "??:??"
end

local function parse_timeline(session_id)
  local session = index.get_session(session_id)
  if not session or session.jsonl_path == "" then
    return {}
  end

  local fd = io.open(session.jsonl_path, "r")
  if not fd then
    return {}
  end

  local events = {}
  for line in fd:lines() do
    local ok, row = pcall(json_decode, line)
    if ok and type(row) == "table" and row.type == "assistant" then
      local msg = row.message
      if msg and type(msg.content) == "table" then
        for _, block in ipairs(msg.content) do
          if type(block) == "table" and block.type == "tool_use" then
            events[#events + 1] = {
              ts = row.timestamp,
              tool = block.name or "unknown",
              summary = extract_summary(block),
              file_path = (block.input or {}).file_path,
            }
          end
        end
      end
    end
  end

  fd:close()
  return events
end

local function close_timeline()
  if timeline_win and vim.api.nvim_win_is_valid(timeline_win) then
    vim.api.nvim_win_close(timeline_win, true)
  end
  if timeline_buf and vim.api.nvim_buf_is_valid(timeline_buf) then
    vim.api.nvim_buf_delete(timeline_buf, { force = true })
  end
  timeline_buf = nil
  timeline_win = nil
  timeline_events = nil
end

function M.show(session_id)
  if not session_id or session_id == "" then
    vim.notify("session_id is required", vim.log.levels.ERROR)
    return
  end

  close_timeline()

  local events = parse_timeline(session_id)
  timeline_events = events

  timeline_buf = vim.api.nvim_create_buf(false, true)
  vim.bo[timeline_buf].buftype = "nofile"
  vim.bo[timeline_buf].filetype = "ClaudeTimeline"
  vim.bo[timeline_buf].bufhidden = "wipe"

  local lines = {}
  local hl_ranges = {}

  lines[1] = " Session Timeline"
  lines[2] = string.rep("─", 38)

  for i, ev in ipairs(events) do
    local time_str = parse_time(ev.ts)
    local icon = TOOL_ICONS[ev.tool] or "  "
    local line = string.format(" %s %s%s", time_str, icon, ev.summary)
    lines[#lines + 1] = line
    hl_ranges[#lines] = TOOL_HL[ev.tool] or "Normal"
  end

  if #events == 0 then
    lines[#lines + 1] = "  (no tool calls)"
  end

  vim.cmd("botright 40vsplit")
  timeline_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(timeline_win, timeline_buf)
  vim.wo[timeline_win].number = false
  vim.wo[timeline_win].relativenumber = false
  vim.wo[timeline_win].signcolumn = "no"
  vim.wo[timeline_win].winfixwidth = true
  vim.wo[timeline_win].wrap = false

  vim.api.nvim_buf_set_lines(timeline_buf, 0, -1, false, lines)
  vim.bo[timeline_buf].modifiable = false

  -- Apply highlights via extmarks
  local ns = vim.api.nvim_create_namespace("claude_timeline")
  for line_nr, hl_group in pairs(hl_ranges) do
    vim.api.nvim_buf_set_extmark(timeline_buf, ns, line_nr - 1, 0, {
      end_row = line_nr,
      hl_group = hl_group,
      hl_eol = true,
    })
  end

  -- Title highlight
  vim.api.nvim_buf_set_extmark(timeline_buf, ns, 0, 0, {
    end_row = 1,
    hl_group = "Title",
    hl_eol = true,
  })

  -- Keymaps
  vim.keymap.set("n", "q", function()
    close_timeline()
  end, { buffer = timeline_buf, desc = "タイムラインを閉じる" })

  vim.keymap.set("n", "<CR>", function()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local ev_idx = row - 2 -- offset for header lines
    if timeline_events and ev_idx >= 1 and ev_idx <= #timeline_events then
      local ev = timeline_events[ev_idx]
      if ev.file_path and ev.file_path ~= "" then
        vim.cmd("wincmd p")
        vim.cmd("edit " .. vim.fn.fnameescape(ev.file_path))
      end
    end
  end, { buffer = timeline_buf, desc = "ファイルを開く" })
end

vim.keymap.set("n", "<leader>ct", function()
  -- Prompt for session ID or use latest
  local sessions = index.list_sessions(vim.fn.getcwd())
  if #sessions == 0 then
    vim.notify("No Claude sessions found", vim.log.levels.WARN)
    return
  end
  M.show(sessions[1].id)
end, { desc = "Claude タイムライン" })

return M
