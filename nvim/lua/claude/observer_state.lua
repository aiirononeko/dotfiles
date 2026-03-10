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

local function coverage_item(label, status, detail)
  return {
    label = label,
    status = status,
    detail = detail,
  }
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

  local items = {
    coverage_item(
      "repro verification",
      #commands > 0 and (commands[1].derived and "weak" or "ok") or "missing",
      #commands > 0 and summarize_text(commands[1].command, 90) or "no reproducible command detected"
    ),
    coverage_item(
      "tests",
      (command_kinds.test or has_tests) and "ok" or "missing",
      (command_kinds.test and "explicit test command detected") or (has_tests and "test files exist but no command was found")
        or "no test entrypoint detected"
    ),
    coverage_item(
      "lint",
      (command_kinds.lint and "ok") or (has_lint_config and "weak") or "missing",
      command_kinds.lint and "lint command detected" or has_lint_config and "lint config exists but no obvious entrypoint"
        or "no lint entrypoint detected"
    ),
    coverage_item(
      "typecheck",
      (command_kinds.typecheck and "ok") or (has_typecheck_config and "weak") or "missing",
      command_kinds.typecheck and "typecheck command detected"
        or has_typecheck_config and "typecheck config exists but no obvious entrypoint"
        or "no typecheck entrypoint detected"
    ),
    coverage_item(
      "build",
      command_kinds.build and "ok" or has_build and "weak" or "missing",
      command_kinds.build and "build command detected" or has_build and "repo has install/build scripts only"
        or "no build entrypoint detected"
    ),
    coverage_item(
      "failure visibility",
      has_ci and "weak" or "missing",
      has_ci and "CI/workflow files exist, but no structured local status log was found"
        or "no structured local failure surface found"
    ),
    coverage_item(
      "agent guidance",
      has_docs and "ok" or "missing",
      has_docs and "repo-native agent guidance exists" or "no repo-native agent guidance detected"
    ),
    coverage_item(
      "handoff artifacts",
      has_plan and "ok" or "missing",
      has_plan and "repo contains plan/handoff artifacts" or "no repo plan/handoff artifact detected"
    ),
    coverage_item(
      "audit trail",
      file_exists((uv.os_homedir() or "") .. "/.claude/history.jsonl") and "weak" or "missing",
      file_exists((uv.os_homedir() or "") .. "/.claude/history.jsonl")
          and "global Claude history exists, but repo-local status logging is absent"
        or "no audit trail detected"
    ),
    coverage_item(
      "safety boundaries",
      has_docs and "weak" or "missing",
      has_docs and "guidance exists, but explicit sandbox assumptions are thin"
        or "no repo-local safety boundary artifact detected"
    ),
  }

  return items
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
  }

  if type(session.jsonl_path) ~= "string" or session.jsonl_path == "" or not file_exists(session.jsonl_path) then
    add_blocker(details.blockers, "session stream is unavailable for this session")
    return details
  end

  local changes = session_index.get_changes(session.id)
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

  if not details.currently_running_task then
    details.currently_running_task = details.latest_prompt or details.task
  end

  if #details.blockers == 0 and details.latest_failure and details.latest_failure.summary then
    add_blocker(details.blockers, details.latest_failure.summary)
  end

  return details
end

local function build_actions(snapshot)
  local actions = {}
  local session = snapshot.session
  local health = snapshot.health

  local failing_test = session and session.latest_verification
  if failing_test and failing_test.kind ~= "test" then
    failing_test = nil
  end
  if failing_test and failing_test.status ~= "failed" then
    failing_test = nil
  end

  actions[#actions + 1] = {
    id = "fix-failing-tests",
    label = "Fix failing tests with Claude Code",
    enabled = failing_test ~= nil,
    detail = failing_test and summarize_text(failing_test.command, 90) or nil,
    reason = failing_test and nil or "no failing test command detected",
    session_id = session and session.id or nil,
    prompt = failing_test and table.concat({
      "Reproduce the failing tests using the exact command below, identify the root cause, implement the smallest correct fix, preserve existing behavior, and add or adjust regression coverage if behavior changed.",
      "",
      "Observed failure:",
      "- session: " .. session.id,
      "- summary: " .. session.summary,
      "- command: " .. failing_test.command,
      "- failure excerpt: " .. (failing_test.summary or "not captured"),
    }, "\n") or nil,
  }

  local rerun_command = session and session.latest_verification and session.latest_verification.command or snapshot.repo_commands[1]
      and snapshot.repo_commands[1].command
  actions[#actions + 1] = {
    id = "rerun-targeted-checks",
    label = "Re-run targeted checks",
    enabled = rerun_command ~= nil,
    detail = rerun_command and summarize_text(rerun_command, 90) or nil,
    reason = rerun_command and nil or "no targeted command available",
    session_id = session and session.id or nil,
    prompt = rerun_command and table.concat({
      "Re-run the targeted verification command below, inspect the exact outcome, and report whether the harness is healthy, degraded, blocked, or failed.",
      "If the command fails, isolate the root cause and implement the smallest correct remediation.",
      "",
      "Observed state:",
      "- overall health: " .. health.state,
      "- selected session: " .. (session and session.summary or "none"),
      "- command: " .. rerun_command,
    }, "\n") or nil,
  }

  local missing = {}
  local weak = {}
  for _, item in ipairs(snapshot.coverage) do
    if item.status == "missing" then
      missing[#missing + 1] = item.label
    elseif item.status == "weak" then
      weak[#weak + 1] = item.label
    end
  end

  actions[#actions + 1] = {
    id = "add-missing-harness",
    label = "Add missing harness",
    enabled = #missing > 0,
    detail = #missing > 0 and table.concat(missing, ", ") or nil,
    reason = #missing > 0 and nil or "no missing harness items",
    prompt = #missing > 0 and table.concat({
      "Add the minimal harness needed for this project to make agent work more reliable.",
      "Prefer lightweight, maintainable artifacts over a giant monolithic instruction file.",
      "Create or update repo-native docs, plans, and verification entrypoints only where they materially improve observability or remediation.",
      "",
      "Missing harness items:",
      "- " .. table.concat(missing, "\n- "),
      "",
      "Repository context:",
      "- current repo: " .. snapshot.cwd,
      "- current health: " .. health.state,
      "- selected session: " .. (session and session.summary or "none"),
    }, "\n") or nil,
  }

  actions[#actions + 1] = {
    id = "strengthen-weak-harness",
    label = "Strengthen weak harness",
    enabled = #weak > 0,
    detail = #weak > 0 and table.concat(weak, ", ") or nil,
    reason = #weak > 0 and nil or "no weak harness items",
    prompt = #weak > 0 and table.concat({
      "Strengthen the weak harness areas below without turning this repository into a giant framework.",
      "Prefer practical, inspectable improvements: better verification entrypoints, clearer failure visibility, and smaller repo-native guidance artifacts.",
      "",
      "Weak harness items:",
      "- " .. table.concat(weak, "\n- "),
      "",
      "Current health:",
      "- state: " .. health.state,
      "- failing checks: " .. tostring(health.failing_checks_count),
      "- blocked: " .. tostring(health.blocked),
    }, "\n") or nil,
  }

  actions[#actions + 1] = {
    id = "open-session-summary",
    label = "Open / inspect session summary",
    enabled = session ~= nil,
    detail = session and session.summary or nil,
    reason = session and nil or "no session available",
    kind = "open_summary",
  }

  return actions
end

local function build_health(snapshot)
  local session = snapshot.session
  if not session then
    return {
      state = "idle",
      current_task = "no active Claude session",
      last_successful_verification_ts = nil,
      failing_checks_count = 0,
      blocked = false,
      active_session_count = snapshot.active_session_count,
    }
  end

  local state_name = "healthy"
  if session.blocked then
    state_name = "blocked"
  elseif session.latest_verification and session.latest_verification.status == "failed" then
    state_name = "failed"
  elseif session.failing_checks_count > 0 or #session.blockers > 0 then
    state_name = "degraded"
  end

  return {
    state = state_name,
    current_task = session.currently_running_task or session.task or session.summary,
    last_successful_verification_ts = session.last_successful_verification_ts,
    failing_checks_count = session.failing_checks_count,
    blocked = session.blocked,
    active_session_count = snapshot.active_session_count,
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
  for _, session in ipairs(sessions) do
    if now_ms - session.last_ts <= ACTIVE_SESSION_WINDOW_MS then
      active_session_count = active_session_count + 1
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
    sessions = sessions,
    selected_session_id = selected_session and selected_session.id or nil,
    session = selected_details,
  }

  snapshot.health = build_health(snapshot)
  snapshot.actions = build_actions(snapshot)

  snapshot.signature = table.concat({
    snapshot.selected_session_id or "none",
    snapshot.health.state,
    tostring(snapshot.health.failing_checks_count),
    tostring(snapshot.active_session_count),
    selected_details and tostring(selected_details.last_successful_verification_ts or 0) or "0",
    selected_details and tostring(selected_details.latest_verification and selected_details.latest_verification.timestamp or 0)
      or "0",
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
