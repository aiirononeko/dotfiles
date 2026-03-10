local uv = vim.uv or vim.loop

local session_index = require("claude.session_index")

local M = {}

local POLL_INTERVAL_MS = 3000
local ACTIVE_SESSION_WINDOW_MS = 15 * 60 * 1000
local BLOCKED_THRESHOLD_MS = 5 * 60 * 1000

local state = {
  timer = nil,
  next_subscriber_id = 0,
  subscribers = {},
}

local function json_decode(text)
  if vim.json and vim.json.decode then
    return vim.json.decode(text)
  end
  return vim.fn.json_decode(text)
end

local function trim(text)
  if type(text) ~= "string" then
    return ""
  end
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function compact_ws(text)
  return trim((text or ""):gsub("[%s\r\n]+", " "))
end

local function truncate_chars(text, max_chars)
  text = text or ""
  if vim.fn.strchars(text) <= max_chars then
    return text
  end
  return vim.fn.strcharpart(text, 0, max_chars - 1) .. "…"
end

local function summarize_text(text, max_chars)
  text = compact_ws(text)
  if text == "" then
    return nil
  end
  return truncate_chars(text, max_chars or 120)
end

local function first_non_empty(...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if type(value) == "string" then
      value = trim(value)
      if value ~= "" then
        return value
      end
    end
  end

  return nil
end

local function seems_path_like(text)
  text = trim(text or "")
  if text == "" then
    return false
  end

  if text:find("/", 1, true) or text:find("\\", 1, true) then
    return true
  end

  if text:match("^[%w%._%-]+%.[%w]+$") then
    return true
  end

  return false
end

local function lower_first(text)
  if type(text) ~= "string" or text == "" then
    return text
  end
  return text:sub(1, 1):lower() .. text:sub(2)
end

local function normalize_intent_text(text, max_chars)
  text = summarize_text(text, max_chars or 96)
  if not text then
    return nil
  end

  local replacements = {
    { "^task:%s*", "" },
    { "^please%s+", "" },
    { "^can you%s+", "" },
    { "^could you%s+", "" },
    { "^i need you to%s+", "" },
    { "^help me%s+", "" },
    { "^work on%s+", "" },
    { "^investigate%s+", "investigating " },
    { "^debug%s+", "debugging " },
    { "^verify%s+", "verifying " },
    { "^reproduce%s+", "reproducing " },
  }

  local normalized = text
  for _, replacement in ipairs(replacements) do
    normalized = normalized:gsub(replacement[1], replacement[2])
  end

  normalized = compact_ws(normalized)
  if normalized == "" then
    return nil
  end

  return lower_first(normalized)
end

local function floor_div(a, b)
  return math.floor(a / b)
end

local function days_from_civil(year, month, day)
  year = year - (month <= 2 and 1 or 0)

  local era
  if year >= 0 then
    era = floor_div(year, 400)
  else
    era = floor_div(year - 399, 400)
  end

  local yoe = year - (era * 400)
  local mp = month + (month > 2 and -3 or 9)
  local doy = floor_div((153 * mp) + 2, 5) + day - 1
  local doe = (yoe * 365) + floor_div(yoe, 4) - floor_div(yoe, 100) + doy
  return (era * 146097) + doe - 719468
end

local function to_timestamp_ms(value)
  if type(value) == "number" then
    if value > 1000000000000 then
      return value
    end
    return math.floor(value * 1000)
  end

  if type(value) ~= "string" or value == "" then
    return nil
  end

  local numeric = tonumber(value)
  if numeric then
    if numeric > 1000000000000 then
      return numeric
    end
    return math.floor(numeric * 1000)
  end

  local year, month, day, hour, minute, second, frac, offset =
    value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)(%.%d+)?(.*)$")
  if not year then
    return nil
  end

  local offset_seconds = 0
  if offset ~= "" and offset ~= "Z" then
    local sign, off_hour, off_min = offset:match("^([+-])(%d%d):?(%d%d)$")
    if not sign then
      return nil
    end
    offset_seconds = ((tonumber(off_hour) * 60) + tonumber(off_min)) * 60
    if sign == "-" then
      offset_seconds = -offset_seconds
    end
  end

  local frac_ms = 0
  if frac and frac ~= "" then
    local digits = frac:sub(2)
    digits = (digits .. "000"):sub(1, 3)
    frac_ms = tonumber(digits) or 0
  end

  local days = days_from_civil(tonumber(year), tonumber(month), tonumber(day))
  local seconds = (days * 86400)
    + (tonumber(hour) * 3600)
    + (tonumber(minute) * 60)
    + tonumber(second)
    - offset_seconds

  return (seconds * 1000) + frac_ms
end

local function file_exists(path)
  return path and uv.fs_stat(path) ~= nil
end

local function read_file(path)
  local fd = io.open(path, "r")
  if not fd then
    return nil
  end
  local content = fd:read("*a")
  fd:close()
  return content
end

local function read_json_file(path)
  local content = read_file(path)
  if not content or content == "" then
    return nil
  end

  local ok, decoded = pcall(json_decode, content)
  if not ok then
    return nil
  end

  return decoded
end

local function list_recent_sessions(cwd)
  local sessions = session_index.list_sessions(cwd)
  table.sort(sessions, function(a, b)
    if a.last_ts == b.last_ts then
      return a.id > b.id
    end
    return a.last_ts > b.last_ts
  end)
  return sessions
end

local function format_age(ts_ms)
  if not ts_ms or ts_ms <= 0 then
    return "never"
  end

  local now_ms = os.time() * 1000
  local delta = math.floor((now_ms - ts_ms) / 1000)

  if delta < 60 then
    return delta .. "s ago"
  end

  if delta < 3600 then
    return math.floor(delta / 60) .. "m ago"
  end

  if delta < 86400 then
    return math.floor(delta / 3600) .. "h ago"
  end

  return math.floor(delta / 86400) .. "d ago"
end

local function format_clock(ts_ms)
  if not ts_ms or ts_ms <= 0 then
    return "n/a"
  end
  return os.date("%m/%d %H:%M", math.floor(ts_ms / 1000))
end

local function shorten_path(path, cwd)
  if type(path) ~= "string" then
    return nil
  end
  local base = cwd
  if base and base:sub(-1) ~= "/" then
    base = base .. "/"
  end
  if base and path:sub(1, #base) == base then
    return path:sub(#base + 1)
  end
  return path
end

local function extract_text_content(content)
  if type(content) == "string" then
    return content
  end

  if type(content) ~= "table" then
    return nil
  end

  local parts = {}
  for _, block in ipairs(content) do
    if type(block) == "string" then
      parts[#parts + 1] = block
    elseif type(block) == "table" then
      if block.type == "text" and type(block.text) == "string" then
        parts[#parts + 1] = block.text
      elseif block.type == "tool_result" then
        local nested = extract_text_content(block.content)
        if nested and nested ~= "" then
          parts[#parts + 1] = nested
        end
      elseif type(block.content) == "string" then
        parts[#parts + 1] = block.content
      end
    end
  end

  if #parts == 0 then
    return nil
  end

  return table.concat(parts, "\n")
end

local function tool_use_summary(name, input)
  input = input or {}

  if name == "Bash" then
    return summarize_text(input.command or "", 80) or "shell command"
  end

  if name == "Read" or name == "Write" or name == "Edit" then
    return vim.fn.fnamemodify(input.file_path or "", ":t")
  end

  if name == "Glob" then
    return summarize_text(input.pattern or "", 80) or "file search"
  end

  if name == "Grep" then
    return summarize_text(input.pattern or input.query or "", 80) or "text search"
  end

  if name == "Agent" then
    return summarize_text(input.description or input.prompt or "", 80) or "sub-agent"
  end

  return summarize_text(name or "task", 80)
end

local function classify_command(command)
  if type(command) ~= "string" or command == "" then
    return nil
  end

  local lowered = command:lower()
  local kinds = {
    { kind = "test", patterns = { " test", "test ", "pytest", "cargo test", "go test", "vitest", "jest", "rspec" } },
    { kind = "lint", patterns = { " lint", "lint ", "eslint", "ruff", "clippy", "shellcheck", "stylua", "luacheck" } },
    { kind = "typecheck", patterns = { "typecheck", "tsc", "pyright", "mypy", "basedpyright" } },
    { kind = "build", patterns = { " build", "build ", "compile", "cargo build", "go build" } },
    { kind = "verify", patterns = { "check", "verify", "nvim --headless", "make ", "just " } },
  }

  for _, entry in ipairs(kinds) do
    for _, pattern in ipairs(entry.patterns) do
      if lowered:find(pattern, 1, true) then
        return entry.kind
      end
    end
  end

  return nil
end

local function collect_nested_events(row, out)
  if row.type ~= "progress" or type(row.data) ~= "table" then
    return
  end

  local nested = row.data.message
  if type(nested) ~= "table" then
    return
  end

  out[#out + 1] = {
    source = "progress",
    kind = nested.type,
    timestamp = to_timestamp_ms(nested.timestamp or row.timestamp),
    message = nested.message,
    raw = nested,
  }
end

local function collect_events(path)
  local fd = io.open(path, "r")
  if not fd then
    return {}
  end

  local events = {}
  for line in fd:lines() do
    local ok, row = pcall(json_decode, line)
    if ok and type(row) == "table" then
      events[#events + 1] = {
        source = "row",
        kind = row.type,
        timestamp = to_timestamp_ms(row.timestamp),
        message = row.message,
        row = row,
      }
      collect_nested_events(row, events)
    end
  end

  fd:close()
  return events
end

local function add_blocker(target, text)
  local summary = summarize_text(text, 120)
  if not summary then
    return
  end
  target[#target + 1] = summary
end

local function infer_what_changed(changes, cwd)
  if #changes == 0 then
    return "no recorded file edits"
  end

  local counts = {}
  local order = {}
  for _, change in ipairs(changes) do
    local path = shorten_path(change.path, cwd) or change.path
    if path and not counts[path] then
      counts[path] = 0
      order[#order + 1] = path
    end
    counts[path] = counts[path] + 1
  end

  local shown = {}
  for i = 1, math.min(3, #order) do
    shown[#shown + 1] = order[i]
  end

  local suffix = ""
  if #order > #shown then
    suffix = string.format(" +%d more", #order - #shown)
  end

  return table.concat(shown, ", ") .. suffix
end

local function collect_verification_commands(cwd)
  local commands = {}

  local package_json = read_json_file(cwd .. "/package.json")
  if type(package_json) == "table" and type(package_json.scripts) == "table" then
    local scripts = package_json.scripts
    if type(scripts.test) == "string" then
      commands[#commands + 1] = { kind = "test", label = "npm test", command = "npm test" }
    end
    if type(scripts.lint) == "string" then
      commands[#commands + 1] = { kind = "lint", label = "npm run lint", command = "npm run lint" }
    end
    if type(scripts.typecheck) == "string" then
      commands[#commands + 1] = { kind = "typecheck", label = "npm run typecheck", command = "npm run typecheck" }
    end
    if type(scripts.build) == "string" then
      commands[#commands + 1] = { kind = "build", label = "npm run build", command = "npm run build" }
    end
  end

  if file_exists(cwd .. "/Cargo.toml") then
    commands[#commands + 1] = { kind = "test", label = "cargo test", command = "cargo test" }
    commands[#commands + 1] = { kind = "lint", label = "cargo clippy", command = "cargo clippy --all-targets --all-features" }
    commands[#commands + 1] = { kind = "build", label = "cargo build", command = "cargo build" }
  end

  if file_exists(cwd .. "/go.mod") then
    commands[#commands + 1] = { kind = "test", label = "go test", command = "go test ./..." }
    commands[#commands + 1] = { kind = "build", label = "go build", command = "go build ./..." }
  end

  if file_exists(cwd .. "/pyproject.toml") or file_exists(cwd .. "/pytest.ini") then
    commands[#commands + 1] = { kind = "test", label = "pytest", command = "pytest" }
  end

  if file_exists(cwd .. "/nvim/init.lua") then
    commands[#commands + 1] = {
      kind = "verify",
      label = "Neovim headless smoke",
      command = "nvim --headless '+qa'",
      derived = true,
    }
  end

  return commands
end

local function select_primary_command(commands)
  local preferred = { verify = 1, test = 2, lint = 3, typecheck = 4, build = 5 }
  local best = nil
  local best_rank = math.huge

  for _, command in ipairs(commands or {}) do
    local rank = preferred[command.kind] or 99
    if command.derived then
      rank = rank + 10
    end
    if not best or rank < best_rank then
      best = command
      best_rank = rank
    end
  end

  return best
end

local function coverage_item(id, label, priority, status, detail, order)
  return {
    id = id,
    label = label,
    priority = priority,
    status = status,
    detail = detail,
    order = order,
  }
end

local function coverage_priority_rank(priority)
  if priority == "required" then
    return 2
  end
  return 1
end

local function coverage_status_rank(status)
  if status == "missing" then
    return 3
  end
  if status == "weak" then
    return 2
  end
  return 1
end

local function sort_coverage_items(items)
  table.sort(items, function(a, b)
    local a_rank = (coverage_status_rank(a.status) * 10) + coverage_priority_rank(a.priority)
    local b_rank = (coverage_status_rank(b.status) * 10) + coverage_priority_rank(b.priority)
    if a_rank == b_rank then
      return (a.order or 99) < (b.order or 99)
    end
    return a_rank > b_rank
  end)

  return items
end

local function has_any(paths)
  for _, path in ipairs(paths) do
    if file_exists(path) then
      return true
    end
  end
  return false
end

local function build_harness_coverage(cwd, commands)
  local has_docs = has_any({
    cwd .. "/CLAUDE.md",
    cwd .. "/AGENTS.md",
    cwd .. "/docs/agent/observer-mode-mvp.md",
    cwd .. "/docs/agent/harness.md",
  })
  local has_plan = has_any({
    cwd .. "/docs/agent/observer-mode-mvp.md",
    cwd .. "/docs/agent",
    cwd .. "/plans",
  })
  local has_ci = has_any({
    cwd .. "/.github/workflows",
    cwd .. "/.gitlab-ci.yml",
  })
  local has_lint_config = has_any({
    cwd .. "/.eslintrc",
    cwd .. "/.eslintrc.js",
    cwd .. "/ruff.toml",
    cwd .. "/.ruff.toml",
    cwd .. "/stylua.toml",
    cwd .. "/.stylua.toml",
    cwd .. "/.luacheckrc",
  })
  local has_typecheck_config = has_any({
    cwd .. "/tsconfig.json",
    cwd .. "/pyrightconfig.json",
    cwd .. "/mypy.ini",
  })
  local has_tests = has_any({
    cwd .. "/tests",
    cwd .. "/test",
    cwd .. "/spec",
  })
  local has_build = has_any({
    cwd .. "/Makefile",
    cwd .. "/justfile",
    cwd .. "/install.sh",
    cwd .. "/install.ps1",
  })

  local command_kinds = {}
  for _, command in ipairs(commands) do
    command_kinds[command.kind] = true
  end

  local primary_command = select_primary_command(commands)

  local items = {
    coverage_item(
      "repro_verification",
      "reproducible verification",
      "required",
      primary_command and (primary_command.derived and "weak" or "ok") or "missing",
      primary_command and summarize_text(primary_command.command, 90) or "no reproducible verification command detected",
      1
    ),
    coverage_item(
      "failure_visibility",
      "failure visibility",
      "required",
      has_ci and "weak" or "missing",
      has_ci and "CI/workflow files exist, but local failure surfaces are still thin"
        or "no structured local failure surface found",
      2
    ),
    coverage_item(
      "tests",
      "tests",
      "required",
      (command_kinds.test or has_tests) and "ok" or "missing",
      (command_kinds.test and "explicit test command detected") or (has_tests and "test files exist but no command was found")
        or "no test entrypoint detected",
      3
    ),
    coverage_item(
      "lint",
      "lint",
      "required",
      (command_kinds.lint and "ok") or (has_lint_config and "weak") or "missing",
      command_kinds.lint and "lint command detected" or has_lint_config and "lint config exists but no obvious entrypoint"
        or "no lint entrypoint detected",
      4
    ),
    coverage_item(
      "typecheck",
      "typecheck",
      "required",
      (command_kinds.typecheck and "ok") or (has_typecheck_config and "weak") or "missing",
      command_kinds.typecheck and "typecheck command detected"
        or has_typecheck_config and "typecheck config exists but no obvious entrypoint"
        or "no typecheck entrypoint detected",
      5
    ),
    coverage_item(
      "build",
      "build",
      "required",
      command_kinds.build and "ok" or has_build and "weak" or "missing",
      command_kinds.build and "build command detected" or has_build and "repo has install/build scripts only"
        or "no build entrypoint detected",
      6
    ),
    coverage_item(
      "handoff_artifacts",
      "handoff artifacts",
      "recommended",
      has_plan and "ok" or "missing",
      has_plan and "repo contains plan or handoff artifacts" or "no repo plan or handoff artifact detected",
      7
    ),
    coverage_item(
      "agent_guidance",
      "agent guidance",
      "recommended",
      has_docs and "ok" or "missing",
      has_docs and "repo-native agent guidance exists" or "no repo-native agent guidance detected",
      8
    ),
    coverage_item(
      "audit_trail",
      "audit trail",
      "recommended",
      file_exists((uv.os_homedir() or "") .. "/.claude/history.jsonl") and "weak" or "missing",
      file_exists((uv.os_homedir() or "") .. "/.claude/history.jsonl")
          and "global Claude history exists, but repo-local status logging is absent"
        or "no audit trail detected",
      9
    ),
    coverage_item(
      "safety_boundaries",
      "safety boundaries",
      "recommended",
      has_docs and "weak" or "missing",
      has_docs and "guidance exists, but explicit sandbox assumptions are thin"
        or "no repo-local safety boundary artifact detected",
      10
    ),
  }

  return sort_coverage_items(items)
end

local function scope_hint_from_changes(changes, cwd)
  if #changes == 0 then
    return nil
  end

  local path = shorten_path(changes[1].path, cwd) or changes[1].path
  local scope = vim.fn.fnamemodify(path, ":t:r")
  if scope == "" then
    scope = path
  end

  scope = compact_ws((scope or ""):gsub("[_%-.]+", " "))
  if scope == "" then
    return nil
  end

  return summarize_text(scope, 40)
end

local function verification_subject(kind)
  if kind == "test" then
    return "tests"
  end
  if kind == "lint" then
    return "lint"
  end
  if kind == "typecheck" then
    return "typecheck"
  end
  if kind == "build" then
    return "build"
  end
  return "verification"
end

local function derive_session_goal(details, scope_hint)
  if details.latest_verification and details.latest_verification.status == "failed" then
    return "reproducing failing " .. verification_subject(details.latest_verification.kind)
  end

  if details.pending_tools[1] and details.pending_tools[1].name == "Bash" then
    local command = summarize_text(details.pending_tools[1].input and details.pending_tools[1].input.command, 60)
    if command then
      return "running " .. command
    end
  end

  local normalized = normalize_intent_text(first_non_empty(details.latest_prompt, details.task, details.summary), 96)
  if normalized and not seems_path_like(normalized) then
    return normalized
  end

  if scope_hint then
    return "working in " .. scope_hint .. " scope"
  end

  if details.latest_verification and details.latest_verification.command then
    return "re-running " .. verification_subject(details.latest_verification.kind)
  end

  return "reviewing selected Claude session"
end

local function derive_session_summary(details)
  local summary = normalize_intent_text(first_non_empty(details.summary, details.latest_prompt, details.task), 84)
  if summary and not seems_path_like(summary) then
    return summary
  end

  return details.goal
end

local function derive_state_transition(details)
  if details.blocked and details.pending_tools[1] then
    return "blocked on " .. (details.pending_tools[1].summary or "long-running tool")
  end

  if details.latest_verification then
    local command = summarize_text(details.latest_verification.command, 52) or verification_subject(details.latest_verification.kind)
    if details.latest_verification.status == "failed" then
      return "failed after " .. command
    end
    return "healthy after " .. command
  end

  if details.pending_tools[1] then
    return "running " .. (details.pending_tools[1].summary or "agent task")
  end

  return "no recent state transition recorded"
end

local function build_session_details(session, cwd)
  local details = {
    id = session.id,
    first_ts = session.first_ts,
    last_ts = session.last_ts,
    msg_count = session.msg_count,
    summary = session.summary,
    task = session.summary,
    latest_prompt = nil,
    touched_files_count = 0,
    recent_files = {},
    what_changed = "no recorded file edits",
    blockers = {},
    latest_verification = nil,
    last_successful_verification_ts = nil,
    failing_checks_count = 0,
    blocked = false,
    currently_running_task = nil,
    latest_failure = nil,
    pending_tools = {},
    goal = nil,
    summary_line = nil,
    current_blocker = nil,
    last_action = nil,
    last_action_ts = nil,
    latest_anomaly = nil,
    last_state_transition = nil,
    current_risk = nil,
  }

  if type(session.jsonl_path) ~= "string" or session.jsonl_path == "" or not file_exists(session.jsonl_path) then
    add_blocker(details.blockers, "session stream is unavailable for this session")
    return details
  end

  local changes = session_index.get_changes(session.id)
  local scope_hint = scope_hint_from_changes(changes, cwd)
  details.touched_files_count = #changes
  details.what_changed = infer_what_changed(changes, cwd)
  for i = 1, math.min(5, #changes) do
    details.recent_files[#details.recent_files + 1] = shorten_path(changes[i].path, cwd) or changes[i].path
  end

  local events = collect_events(session.jsonl_path)
  local pending_tools = {}

  for _, event in ipairs(events) do
    if event.kind == "last-prompt" and event.row then
      details.latest_prompt = summarize_text(event.row.lastPrompt, 140) or details.latest_prompt
    elseif event.kind == "user" and event.row and not event.row.isMeta then
      local prompt_text = extract_text_content(event.row.message and event.row.message.content)
      local prompt_summary = summarize_text(prompt_text, 140)
      if prompt_summary then
        details.task = prompt_summary
        details.latest_prompt = prompt_summary
      end
    elseif event.kind == "assistant" and type(event.message) == "table" and type(event.message.content) == "table" then
      for _, block in ipairs(event.message.content) do
        if type(block) == "table" and block.type == "tool_use" then
          pending_tools[block.id] = {
            id = block.id,
            name = block.name,
            input = block.input or {},
            timestamp = event.timestamp or session.last_ts,
            summary = tool_use_summary(block.name, block.input),
          }
          details.last_action = "started " .. pending_tools[block.id].summary
          details.last_action_ts = pending_tools[block.id].timestamp
        elseif type(block) == "table" and block.type == "text" then
          local assistant_summary = summarize_text(block.text, 140)
          if assistant_summary and details.summary == session.summary then
            details.summary = assistant_summary
          end
        end
      end
    elseif event.kind == "user" and type(event.message) == "table" and type(event.message.content) == "table" then
      for _, block in ipairs(event.message.content) do
        if type(block) == "table" and block.type == "tool_result" then
          local tool = pending_tools[block.tool_use_id]
          local text = summarize_text(extract_text_content(block.content), 140)
          local verification_kind = tool and tool.name == "Bash" and classify_command(tool.input.command or "")
          if verification_kind then
            local verification = {
              kind = verification_kind,
              command = tool.input.command or "",
              status = block.is_error and "failed" or "ok",
              timestamp = event.timestamp or tool.timestamp,
              summary = text,
            }
            details.latest_verification = verification
            details.last_action = "ran " .. (summarize_text(verification.command, 64) or verification_subject(verification.kind))
            details.last_action_ts = verification.timestamp
            if verification.status == "ok" then
              details.last_successful_verification_ts = verification.timestamp
            else
              details.failing_checks_count = details.failing_checks_count + 1
              details.latest_failure = verification
              add_blocker(details.blockers, verification.summary or verification.command)
            end
          elseif block.is_error then
            details.latest_failure = {
              kind = tool and tool.name or "task",
              summary = text or (tool and tool.summary) or "command failed",
              timestamp = event.timestamp or (tool and tool.timestamp) or session.last_ts,
            }
            details.last_action = "tool error from " .. ((tool and tool.summary) or "task")
            details.last_action_ts = details.latest_failure.timestamp
            add_blocker(details.blockers, text or (tool and tool.summary) or "tool failure")
          end

          pending_tools[block.tool_use_id] = nil
        end
      end
    end
  end

  local now_ms = os.time() * 1000
  for _, tool in pairs(pending_tools) do
    details.pending_tools[#details.pending_tools + 1] = tool
    if not details.currently_running_task then
      details.currently_running_task = tool.summary
    end
    if now_ms - (tool.timestamp or now_ms) >= BLOCKED_THRESHOLD_MS then
      details.blocked = true
    end
  end

  table.sort(details.pending_tools, function(a, b)
    return (a.timestamp or 0) > (b.timestamp or 0)
  end)

  if not details.currently_running_task then
    details.currently_running_task = details.latest_prompt or details.task
  end

  if #details.blockers == 0 and details.latest_failure and details.latest_failure.summary then
    add_blocker(details.blockers, details.latest_failure.summary)
  end

  details.goal = derive_session_goal(details, scope_hint)
  details.summary_line = derive_session_summary(details)
  details.current_blocker = details.blockers[1]
  if not details.current_blocker and details.blocked and details.pending_tools[1] then
    details.current_blocker = "no result yet for " .. (details.pending_tools[1].summary or "long-running tool")
  end
  if not details.last_action and details.pending_tools[1] then
    details.last_action = "running " .. (details.pending_tools[1].summary or "agent task")
    details.last_action_ts = details.pending_tools[1].timestamp
  end
  if not details.last_action then
    details.last_action = "no recent action recorded"
  end
  details.latest_anomaly = (details.latest_failure and (details.latest_failure.summary or details.latest_failure.kind))
    or (details.blocked and details.pending_tools[1] and ("stuck on " .. (details.pending_tools[1].summary or "long-running tool")))
    or nil
  details.last_state_transition = derive_state_transition(details)
  details.current_risk = details.current_blocker
    or details.latest_anomaly
    or (details.pending_tools[1] and "work is still in progress")
    or "no active intervention needed"

  return details
end

local function coverage_lookup(items)
  local map = {}
  for _, item in ipairs(items or {}) do
    map[item.id] = item
  end
  return map
end

local function collect_coverage_labels(items, predicate)
  local labels = {}
  for _, item in ipairs(items or {}) do
    if predicate(item) then
      labels[#labels + 1] = item.label
    end
  end
  return labels
end

local function bullet_lines(items)
  if #items == 0 then
    return "- none"
  end
  return "- " .. table.concat(items, "\n- ")
end

local function session_context_label(session)
  if not session then
    return "none"
  end
  return session.goal or session.summary_line or session.summary or "selected Claude session"
end

local function build_fix_failing_tests_prompt(snapshot, session, verification)
  return table.concat({
    "The observer reports a failing test verification for this repo.",
    "First reproduce the failure with the exact command below.",
    "Then identify the root cause, implement the smallest correct fix, preserve existing behavior unless an intentional change is required, and add or adjust regression coverage around the bug.",
    "Re-run the same command before finishing.",
    "",
    "Observed issue:",
    "- repo: " .. snapshot.cwd,
    "- session goal: " .. session_context_label(session),
    "- command: " .. (verification.command or "not captured"),
    "- failure excerpt: " .. (verification.summary or "not captured"),
  }, "\n")
end

local function build_rerun_verification_prompt(snapshot, session, command, observed_issue)
  return table.concat({
    "The observer reports a degraded or blocked verification path for this repo.",
    "First reproduce the observed state with the exact command below.",
    "If the command fails, isolate the root cause and implement the smallest correct fix.",
    "Preserve existing behavior unless an intentional change is required, and add or adjust regression coverage when the fix changes behavior.",
    "Re-run the same command before finishing.",
    "",
    "Observed issue:",
    "- repo: " .. snapshot.cwd,
    "- overall health: " .. snapshot.health.state,
    "- selected session: " .. session_context_label(session),
    "- command: " .. (command or "not captured"),
    "- observation: " .. (observed_issue or "observer requested targeted verification"),
  }, "\n")
end

local function build_missing_harness_prompt(snapshot, session, items)
  local lines = {
    "The observer reports missing harness coverage for this repo.",
    "First inspect the repo's existing scripts and docs.",
    "Then add only the minimum maintainable harness needed so agent work becomes reproducible and diagnosable.",
    "Prefer repo-native verification entrypoints, structured failure surfaces, and small local docs over a giant monolithic instruction file.",
    "Keep scope narrow to the missing items below and verify any new or updated entrypoint before finishing.",
    "",
    "Missing harness items:",
    bullet_lines(items),
    "",
    "Observed state:",
    "- repo: " .. snapshot.cwd,
    "- overall health: " .. snapshot.health.state,
    "- selected session: " .. session_context_label(session),
  }

  if session and session.latest_verification and session.latest_verification.command then
    lines[#lines + 1] = "- last command seen: " .. session.latest_verification.command
  end

  return table.concat(lines, "\n")
end

local function build_weak_harness_prompt(snapshot, session, items)
  local lines = {
    "The observer reports weak harness coverage for this repo.",
    "First inspect the repo's existing scripts, docs, and failure surfaces.",
    "Then strengthen only the weak areas below with the smallest maintainable change.",
    "Prefer clearer verification entrypoints, better local failure visibility, and focused repo-native guidance over broad framework work.",
    "Preserve current behavior unless intentional changes are required, and verify any changed harness before finishing.",
    "",
    "Weak harness items:",
    bullet_lines(items),
    "",
    "Observed state:",
    "- repo: " .. snapshot.cwd,
    "- overall health: " .. snapshot.health.state,
    "- selected session: " .. session_context_label(session),
  }

  if session and session.current_blocker then
    lines[#lines + 1] = "- current blocker: " .. session.current_blocker
  end

  return table.concat(lines, "\n")
end

local function build_blocked_session_prompt(snapshot, session, command)
  local lines = {
    "The observer reports a blocked session for this repo.",
    "First inspect the selected session and reproduce the blockage if a command is available.",
    "Then unblock it with the smallest correct fix, preserve existing behavior unless an intentional change is required, and verify the unblock before finishing.",
    "",
    "Observed issue:",
    "- repo: " .. snapshot.cwd,
    "- session goal: " .. session_context_label(session),
    "- blocker: " .. (session and session.current_blocker or "session is blocked"),
    "- pending task: " .. (session and session.currently_running_task or "not captured"),
  }

  if command then
    lines[#lines + 1] = "- command: " .. command
  end

  return table.concat(lines, "\n")
end

local function build_actions(snapshot)
  local actions = {}
  local session = snapshot.session
  local coverage = coverage_lookup(snapshot.coverage)
  local primary_repo_command = select_primary_command(snapshot.repo_commands)
  local rerun_command = session and session.latest_verification and session.latest_verification.command
    or primary_repo_command and primary_repo_command.command
  local session_id = session and session.id or nil

  local function add_action(action)
    if not action or #actions >= 5 then
      return
    end
    for _, existing in ipairs(actions) do
      if existing.id == action.id then
        return
      end
    end
    actions[#actions + 1] = action
  end

  local function action_command_detail(command)
    return summarize_text(command, 56) or "command"
  end

  local latest_verification = session and session.latest_verification or nil
  if latest_verification and latest_verification.status == "failed" and latest_verification.kind == "test" then
    add_action({
      id = "fix-failing-tests",
      label = "Reproduce and fix failing tests",
      primary = true,
      enabled = true,
      detail = "Claude: reproduce `" .. action_command_detail(latest_verification.command) .. "`, smallest fix, regression coverage",
      session_id = session_id,
      prompt = build_fix_failing_tests_prompt(snapshot, session, latest_verification),
    })
  elseif latest_verification and latest_verification.status == "failed" then
    add_action({
      id = "fix-blocker",
      label = "Reproduce and fix blocker",
      primary = true,
      enabled = true,
      detail = "Claude: reproduce `" .. action_command_detail(latest_verification.command) .. "`, smallest fix, preserve behavior",
      session_id = session_id,
      prompt = build_rerun_verification_prompt(
        snapshot,
        session,
        latest_verification.command,
        session.current_blocker or latest_verification.summary
      ),
    })
  elseif session and session.blocked then
    local blocked_command = session.pending_tools[1] and session.pending_tools[1].input and session.pending_tools[1].input.command
      or rerun_command
    add_action({
      id = "unblock-session",
      label = "Inspect and unblock session",
      primary = true,
      enabled = true,
      detail = blocked_command and ("Claude: inspect blockage and reproduce `" .. action_command_detail(blocked_command) .. "`")
        or "Claude: inspect blockage, recover progress, keep scope narrow",
      session_id = session_id,
      prompt = build_blocked_session_prompt(snapshot, session, blocked_command),
    })
  elseif coverage.repro_verification and coverage.repro_verification.status ~= "ok" then
    local missing_repro = coverage.repro_verification.status == "missing"
    add_action({
      id = missing_repro and "add-verification-command" or "strengthen-verification-command",
      label = missing_repro and "Add missing verification command" or "Strengthen verification command",
      primary = true,
      enabled = true,
      detail = missing_repro and "Claude: inspect scripts/docs, add repo-native verification entrypoint"
        or "Claude: tighten the current verification entrypoint and make it reproducible",
      session_id = session_id,
      prompt = missing_repro
        and build_missing_harness_prompt(snapshot, session, { "reproducible verification" })
        or build_weak_harness_prompt(snapshot, session, { "reproducible verification" }),
    })
  elseif rerun_command then
    add_action({
      id = "rerun-targeted-verification",
      label = "Re-run targeted verification",
      primary = true,
      enabled = true,
      detail = "Claude: reproduce `" .. action_command_detail(rerun_command) .. "`, report state, fix only if failing",
      session_id = session_id,
      prompt = build_rerun_verification_prompt(snapshot, session, rerun_command, session and session.current_risk or nil),
    })
  end

  if coverage.repro_verification and coverage.repro_verification.status ~= "ok" then
    local missing_repro = coverage.repro_verification.status == "missing"
    add_action({
      id = missing_repro and "add-verification-command" or "strengthen-verification-command",
      label = missing_repro and "Add missing verification command" or "Strengthen verification command",
      enabled = true,
      detail = missing_repro and "Claude: inspect scripts/docs, add repo-native verification entrypoint"
        or "Claude: tighten the current verification entrypoint and document how to run it",
      session_id = session_id,
      prompt = missing_repro
        and build_missing_harness_prompt(snapshot, session, { "reproducible verification" })
        or build_weak_harness_prompt(snapshot, session, { "reproducible verification" }),
    })
  end

  if coverage.failure_visibility and coverage.failure_visibility.status ~= "ok" then
    local missing_visibility = coverage.failure_visibility.status == "missing"
    add_action({
      id = missing_visibility and "add-failure-visibility" or "improve-failure-visibility",
      label = missing_visibility and "Add local failure visibility" or "Improve local failure visibility",
      enabled = true,
      detail = missing_visibility and "Claude: add a small local failure surface for faster diagnosis"
        or "Claude: strengthen existing failure reporting without widening scope",
      session_id = session_id,
      prompt = missing_visibility
        and build_missing_harness_prompt(snapshot, session, { "failure visibility" })
        or build_weak_harness_prompt(snapshot, session, { "failure visibility" }),
    })
  end

  local targeted = {
    repro_verification = true,
    failure_visibility = true,
  }
  local missing = collect_coverage_labels(snapshot.coverage, function(item)
    return item.status == "missing" and not targeted[item.id]
  end)
  local weak = collect_coverage_labels(snapshot.coverage, function(item)
    return item.status == "weak" and not targeted[item.id]
  end)

  if #missing > 0 then
    add_action({
      id = "add-missing-harness",
      label = "Add missing harness",
      enabled = true,
      detail = "Claude: add only the missing repo-native harness items",
      session_id = session_id,
      prompt = build_missing_harness_prompt(snapshot, session, missing),
    })
  elseif #weak > 0 then
    add_action({
      id = "strengthen-weak-harness",
      label = "Strengthen weak harness",
      enabled = true,
      detail = "Claude: strengthen weak harness with minimal, maintainable changes",
      session_id = session_id,
      prompt = build_weak_harness_prompt(snapshot, session, weak),
    })
  end

  add_action({
    id = "open-session-summary",
    label = "Inspect session detail",
    enabled = session ~= nil,
    detail = session and (session.summary_line or session.summary) or nil,
    reason = session and nil or "no session available",
    kind = "open_summary",
  })

  return actions
end

local function build_health(snapshot)
  local active_sessions = snapshot.active_sessions or {}
  local blocked_count = 0
  local failing_checks = 0
  local failed_session_count = 0
  local degraded_session_count = 0
  local last_good_ts = nil
  local blocked_activity = nil
  local running_activity = nil

  for _, session in ipairs(active_sessions) do
    failing_checks = failing_checks + (session.failing_checks_count or 0)
    if session.blocked then
      blocked_count = blocked_count + 1
      blocked_activity = blocked_activity or session.currently_running_task or session.goal
    end
    if session.pending_tools and session.pending_tools[1] and not running_activity then
      running_activity = session.pending_tools[1].summary or session.currently_running_task or session.goal
    end
    if session.latest_verification and session.latest_verification.status == "failed" then
      failed_session_count = failed_session_count + 1
    elseif session.failing_checks_count > 0 or (session.blockers and #session.blockers > 0) then
      degraded_session_count = degraded_session_count + 1
    end
    if session.last_successful_verification_ts and ((not last_good_ts) or session.last_successful_verification_ts > last_good_ts) then
      last_good_ts = session.last_successful_verification_ts
    end
  end

  local required_missing_count = 0
  local required_weak_count = 0
  for _, item in ipairs(snapshot.coverage or {}) do
    if item.priority == "required" and item.status == "missing" then
      required_missing_count = required_missing_count + 1
    elseif item.priority == "required" and item.status == "weak" then
      required_weak_count = required_weak_count + 1
    end
  end

  local state_name = "healthy"
  if blocked_count > 0 then
    state_name = "blocked"
  elseif failed_session_count > 0 then
    state_name = "failed"
  elseif failing_checks > 0 or degraded_session_count > 0 or required_missing_count > 0 or required_weak_count > 0 then
    state_name = "degraded"
  elseif snapshot.active_session_count == 0 then
    state_name = "idle"
  end

  local activity = "observer idle"
  if blocked_activity then
    activity = "stuck on " .. blocked_activity
  elseif running_activity then
    activity = "monitoring " .. running_activity
  elseif snapshot.active_session_count > 0 then
    activity = "monitoring active agent sessions"
  elseif required_missing_count > 0 or required_weak_count > 0 then
    activity = "harness needs intervention"
  end

  return {
    state = state_name,
    activity = activity,
    last_successful_verification_ts = last_good_ts,
    failing_checks_count = failing_checks,
    blocked = blocked_count > 0,
    blocked_session_count = blocked_count,
    active_session_count = snapshot.active_session_count,
    required_missing_count = required_missing_count,
    required_weak_count = required_weak_count,
    next_step = nil,
  }
end

local function build_snapshot(opts)
  opts = opts or {}

  local cwd = opts.cwd or vim.fn.getcwd()
  local sessions = list_recent_sessions(cwd)
  local selected_session_id = opts.session_id

  if selected_session_id then
    local found = false
    for _, session in ipairs(sessions) do
      if session.id == selected_session_id then
        found = true
        break
      end
    end
    if not found then
      selected_session_id = nil
    end
  end

  local selected_session = nil
  if #sessions > 0 then
    if selected_session_id then
      for _, session in ipairs(sessions) do
        if session.id == selected_session_id then
          selected_session = session
          break
        end
      end
    end
    selected_session = selected_session or sessions[1]
  end

  local active_session_count = 0
  local now_ms = os.time() * 1000
  local active_sessions = {}
  for _, session in ipairs(sessions) do
    if now_ms - session.last_ts <= ACTIVE_SESSION_WINDOW_MS then
      active_session_count = active_session_count + 1
      active_sessions[#active_sessions + 1] = build_session_details(session, cwd)
    end
  end

  local repo_commands = collect_verification_commands(cwd)
  local coverage = build_harness_coverage(cwd, repo_commands)
  local selected_details = selected_session and build_session_details(selected_session, cwd) or nil

  local snapshot = {
    cwd = cwd,
    repo_commands = repo_commands,
    coverage = coverage,
    active_session_count = active_session_count,
    active_sessions = active_sessions,
    sessions = sessions,
    selected_session_id = selected_session and selected_session.id or nil,
    session = selected_details,
  }

  snapshot.health = build_health(snapshot)
  snapshot.actions = build_actions(snapshot)
  for _, action in ipairs(snapshot.actions) do
    if action.enabled and action.kind ~= "open_summary" then
      snapshot.health.next_step = action.label
      break
    end
  end
  if not snapshot.health.next_step then
    snapshot.health.next_step = snapshot.health.state == "healthy" and "No intervention needed" or "Inspect session detail"
  end

  snapshot.signature = table.concat({
    snapshot.selected_session_id or "none",
    snapshot.health.state,
    tostring(snapshot.health.failing_checks_count),
    tostring(snapshot.active_session_count),
    selected_details and tostring(selected_details.last_successful_verification_ts or 0) or "0",
    selected_details and tostring(selected_details.latest_verification and selected_details.latest_verification.timestamp or 0)
      or "0",
    table.concat(vim.tbl_map(function(item)
      return item.id .. ":" .. item.status
    end, snapshot.coverage), ","),
    snapshot.actions[1] and snapshot.actions[1].id or "none",
  }, "|")

  return snapshot
end

local function notify_subscriber(id, subscriber)
  local ok, snapshot = pcall(build_snapshot, subscriber.opts)
  if not ok then
    vim.schedule(function()
      vim.notify("claude.observer_state failed: " .. snapshot, vim.log.levels.ERROR)
    end)
    return
  end

  if snapshot.signature == subscriber.last_signature then
    return
  end

  subscriber.last_signature = snapshot.signature
  vim.schedule(function()
    if state.subscribers[id] then
      subscriber.callback(snapshot)
    end
  end)
end

local function ensure_timer()
  if state.timer then
    return
  end

  state.timer = uv.new_timer()
  state.timer:start(POLL_INTERVAL_MS, POLL_INTERVAL_MS, vim.schedule_wrap(function()
    for id, subscriber in pairs(state.subscribers) do
      notify_subscriber(id, subscriber)
    end
  end))
end

local function stop_timer_if_idle()
  if next(state.subscribers) ~= nil or not state.timer then
    return
  end

  state.timer:stop()
  state.timer:close()
  state.timer = nil
end

function M.get_snapshot(opts)
  return build_snapshot(opts)
end

function M.subscribe(opts, callback)
  state.next_subscriber_id = state.next_subscriber_id + 1
  local id = state.next_subscriber_id
  state.subscribers[id] = {
    opts = opts or {},
    callback = callback,
    last_signature = nil,
  }

  ensure_timer()
  notify_subscriber(id, state.subscribers[id])
  return id
end

function M.update_subscription(id, opts)
  if not state.subscribers[id] then
    return
  end
  state.subscribers[id].opts = opts or {}
  state.subscribers[id].last_signature = nil
  notify_subscriber(id, state.subscribers[id])
end

function M.unsubscribe(id)
  state.subscribers[id] = nil
  stop_timer_if_idle()
end

function M.describe_verification(verification)
  if not verification then
    return "none recorded"
  end

  local parts = {
    verification.status,
    verification.kind,
    summarize_text(verification.command, 70) or "command",
  }

  return table.concat(parts, "  ")
end

function M.format_age(ts_ms)
  return format_age(ts_ms)
end

function M.format_clock(ts_ms)
  return format_clock(ts_ms)
end

return M
