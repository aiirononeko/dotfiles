local uv = vim.uv or vim.loop

local M = {}

local HOME = uv.os_homedir()
local CLAUDE_DIR = HOME .. "/.claude"
local HISTORY_PATH = CLAUDE_DIR .. "/history.jsonl"
local PROJECTS_DIR = CLAUDE_DIR .. "/projects"
local CACHE_DIR = vim.fn.stdpath("cache") .. "/claude-sessions"
local HISTORY_CACHE_PATH = CACHE_DIR .. "/history-index.json"

local state = {
  history = nil,
  changes = {},
}

local function json_decode(text)
  if vim.json and vim.json.decode then
    return vim.json.decode(text)
  end
  return vim.fn.json_decode(text)
end

local function json_encode(value)
  if vim.json and vim.json.encode then
    return vim.json.encode(value)
  end
  return vim.fn.json_encode(value)
end

local function ensure_cache_dir()
  vim.fn.mkdir(CACHE_DIR, "p")
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

local function write_file(path, content)
  ensure_cache_dir()

  local fd = io.open(path, "w")
  if not fd then
    return false
  end

  fd:write(content)
  fd:close()
  return true
end

local function read_json_file(path)
  local content = read_file(path)
  if not content or content == "" then
    return nil
  end

  local ok, decoded = pcall(json_decode, content)
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  return decoded
end

local function write_json_file(path, value)
  local ok, encoded = pcall(json_encode, value)
  if not ok then
    return false
  end

  return write_file(path, encoded)
end

local function stat_mtime_ms(path)
  local stat = uv.fs_stat(path)
  if not stat or not stat.mtime then
    return nil
  end

  local sec = stat.mtime.sec or stat.mtime.tv_sec or 0
  local nsec = stat.mtime.nsec or stat.mtime.tv_nsec or 0
  return (sec * 1000) + math.floor(nsec / 1000000)
end

local function normalize_path(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end

  if vim.fs and vim.fs.normalize then
    local ok, normalized = pcall(vim.fs.normalize, path)
    if ok and normalized and normalized ~= "" then
      path = normalized
    end
  end

  if #path > 1 then
    path = path:gsub("/+$", "")
  end

  return path
end

local function trim(text)
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function compact_ws(text)
  return text:gsub("[%s\r\n]+", " ")
end

local function truncate_chars(text, max_chars)
  if vim.fn.strchars(text) <= max_chars then
    return text
  end

  return vim.fn.strcharpart(text, 0, max_chars)
end

local function to_summary(text)
  if type(text) ~= "string" then
    return nil
  end

  text = trim(compact_ws(text))
  if text == "" or text:sub(1, 1) == "/" then
    return nil
  end

  return truncate_chars(text, 80)
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

local function session_sort(a, b)
  if a.last_ts == b.last_ts then
    return a.id > b.id
  end
  return a.last_ts > b.last_ts
end

local function project_to_key(project)
  if type(project) ~= "string" or project == "" then
    return nil
  end

  local key = project:gsub("/", "-")
  if key:sub(1, 1) ~= "-" then
    key = "-" .. key
  end

  return key
end

local function session_jsonl_path(project, session_id)
  local key = project_to_key(project)
  if not key or not session_id then
    return nil
  end

  return string.format("%s/%s/%s.jsonl", PROJECTS_DIR, key, session_id)
end

local function decode_json_line(line)
  if not line or line == "" then
    return nil
  end

  local ok, decoded = pcall(json_decode, line)
  if not ok or type(decoded) ~= "table" then
    return nil
  end

  return decoded
end

local function clone_session(session)
  if not session then
    return nil
  end

  return {
    id = session.id,
    project = session.project,
    first_ts = session.first_ts,
    last_ts = session.last_ts,
    summary = session.summary,
    msg_count = session.msg_count,
    jsonl_path = session.jsonl_path,
  }
end

local function clone_change(change)
  return {
    path = change.path,
    kind = change.kind,
    patch = vim.deepcopy(change.patch),
    original = change.original,
    user_modified = change.user_modified,
  }
end

local function build_history_index()
  local index = {
    history_mtime = stat_mtime_ms(HISTORY_PATH) or 0,
    sessions = {},
    by_id = {},
  }

  local fd = io.open(HISTORY_PATH, "r")
  if not fd then
    return index
  end

  for line in fd:lines() do
    local entry = decode_json_line(line)
    if entry and entry.sessionId then
      local session_id = tostring(entry.sessionId)
      local ts = to_timestamp_ms(entry.timestamp) or 0
      local project = entry.project or ""

      local session = index.by_id[session_id]
      if not session then
        session = {
          id = session_id,
          project = project,
          first_ts = ts,
          last_ts = ts,
          summary = "",
          msg_count = 0,
          jsonl_path = session_jsonl_path(project, session_id) or "",
        }
        index.by_id[session_id] = session
        index.sessions[#index.sessions + 1] = session
      else
        if session.project == "" and project ~= "" then
          session.project = project
          session.jsonl_path = session_jsonl_path(project, session_id) or ""
        end

        if ts > 0 then
          if session.first_ts == 0 or ts < session.first_ts then
            session.first_ts = ts
          end
          if ts > session.last_ts then
            session.last_ts = ts
          end
        end
      end

      session.msg_count = session.msg_count + 1

      if session.summary == "" and not entry.isMeta then
        local summary = to_summary(entry.display)
        if summary then
          session.summary = summary
        end
      end
    end
  end

  fd:close()

  for _, session in ipairs(index.sessions) do
    if session.summary == "" then
      session.summary = "(no prompt)"
    end
  end

  table.sort(index.sessions, session_sort)
  return index
end

local function load_history_cache(history_mtime)
  local payload = read_json_file(HISTORY_CACHE_PATH)
  if not payload or tonumber(payload.history_mtime) ~= history_mtime then
    return nil
  end

  if type(payload.sessions) ~= "table" then
    return nil
  end

  local index = {
    history_mtime = history_mtime,
    sessions = {},
    by_id = {},
  }

  for _, raw in ipairs(payload.sessions) do
    if type(raw) == "table" and raw.id then
      local session = {
        id = tostring(raw.id),
        project = raw.project or "",
        first_ts = tonumber(raw.first_ts) or 0,
        last_ts = tonumber(raw.last_ts) or 0,
        summary = raw.summary or "(no prompt)",
        msg_count = tonumber(raw.msg_count) or 0,
        jsonl_path = raw.jsonl_path or session_jsonl_path(raw.project, raw.id) or "",
      }
      index.sessions[#index.sessions + 1] = session
      index.by_id[session.id] = session
    end
  end

  table.sort(index.sessions, session_sort)
  return index
end

local function persist_history_cache(index)
  local sessions = {}
  for _, session in ipairs(index.sessions) do
    sessions[#sessions + 1] = clone_session(session)
  end

  write_json_file(HISTORY_CACHE_PATH, {
    history_mtime = index.history_mtime,
    sessions = sessions,
  })
end

local function ensure_history_index()
  local history_mtime = stat_mtime_ms(HISTORY_PATH) or 0

  if state.history and state.history.history_mtime == history_mtime then
    return state.history
  end

  local cached = load_history_cache(history_mtime)
  if cached then
    state.history = cached
    return cached
  end

  local rebuilt = build_history_index()
  state.history = rebuilt
  persist_history_cache(rebuilt)
  return rebuilt
end

local function session_cache_path(session_id)
  return string.format("%s/%s.json", CACHE_DIR, session_id)
end

local function normalize_change(raw)
  if type(raw) ~= "table" or type(raw.path) ~= "string" or raw.path == "" then
    return nil
  end

  return {
    path = raw.path,
    kind = raw.kind or "edit",
    patch = raw.patch,
    original = raw.original,
    user_modified = raw.user_modified == true,
  }
end

local function load_changes_cache(session_id, jsonl_path, mtime)
  local memory = state.changes[session_id]
  if memory and memory.path == jsonl_path and memory.mtime == mtime then
    return memory.items
  end

  local payload = read_json_file(session_cache_path(session_id))
  if not payload then
    return nil
  end

  if payload.path ~= jsonl_path or tonumber(payload.mtime) ~= mtime or type(payload.items) ~= "table" then
    return nil
  end

  local items = {}
  for _, raw in ipairs(payload.items) do
    local change = normalize_change(raw)
    if change then
      items[#items + 1] = change
    end
  end

  state.changes[session_id] = {
    path = jsonl_path,
    mtime = mtime,
    items = items,
  }

  return items
end

local function persist_changes_cache(session_id, jsonl_path, mtime, items)
  local payload_items = {}
  for _, item in ipairs(items) do
    payload_items[#payload_items + 1] = clone_change(item)
  end

  write_json_file(session_cache_path(session_id), {
    path = jsonl_path,
    mtime = mtime,
    items = payload_items,
  })
end

local function build_changes(session)
  local jsonl_path = session and session.jsonl_path or nil
  if not jsonl_path or jsonl_path == "" then
    return {}
  end

  local fd = io.open(jsonl_path, "r")
  if not fd then
    return {}
  end

  local items = {}

  for line in fd:lines() do
    local entry = decode_json_line(line)
    if entry and entry.type == "user" and type(entry.toolUseResult) == "table" then
      local result = entry.toolUseResult
      if type(result.filePath) == "string" and result.filePath ~= "" and result.type ~= "text" then
        local kind = "edit"
        if result.type == "create" then
          kind = "create"
        elseif result.type == "update" then
          kind = "update"
        end

        items[#items + 1] = {
          path = result.filePath,
          kind = kind,
          patch = result.structuredPatch,
          original = result.originalFile,
          user_modified = result.userModified == true,
        }
      end
    end
  end

  fd:close()
  return items
end

function M.list_sessions(cwd)
  local index = ensure_history_index()
  local filter = normalize_path(cwd)
  local sessions = {}

  for _, session in ipairs(index.sessions) do
    if not filter or normalize_path(session.project) == filter then
      sessions[#sessions + 1] = clone_session(session)
    end
  end

  return sessions
end

function M.get_session(session_id)
  if type(session_id) ~= "string" or session_id == "" then
    return nil
  end

  local index = ensure_history_index()
  return clone_session(index.by_id[session_id])
end

function M.get_changes(session_id)
  if type(session_id) ~= "string" or session_id == "" then
    return {}
  end

  local session = ensure_history_index().by_id[session_id]
  if not session or session.jsonl_path == "" then
    return {}
  end

  local mtime = stat_mtime_ms(session.jsonl_path) or 0
  local cached = load_changes_cache(session_id, session.jsonl_path, mtime)
  if cached then
    local copied = {}
    for _, change in ipairs(cached) do
      copied[#copied + 1] = clone_change(change)
    end
    return copied
  end

  local items = build_changes(session)
  state.changes[session_id] = {
    path = session.jsonl_path,
    mtime = mtime,
    items = items,
  }
  persist_changes_cache(session_id, session.jsonl_path, mtime, items)

  local copied = {}
  for _, change in ipairs(items) do
    copied[#copied + 1] = clone_change(change)
  end
  return copied
end

function M.invalidate()
  state.history = nil
  state.changes = {}
  vim.fn.delete(CACHE_DIR, "rf")
end

return M
