local renderer = require("neo-tree.ui.renderer")
local session_index = require("claude.session_index")

local script_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

local M = {
  name = "claude_sessions",
  display_name = " Claude",
}

-- Load components/commands via dofile() because vim.loader maps the
-- "neo-tree" top-level module to the plugin directory and skips
-- ~/.config/nvim/lua/ for sub-modules.
M.components = dofile(script_dir .. "components.lua")
M.commands = dofile(script_dir .. "commands.lua")

M.default_config = {
  renderers = {
    directory = {
      { "indent" },
      { "icon" },
      { "name" },
    },
    session = {
      { "indent" },
      { "icon" },
      { "name" },
    },
    file = {
      { "indent" },
      { "icon" },
      { "name" },
    },
  },
}

local function format_date(ts_ms)
  local ts_sec = math.floor(ts_ms / 1000)
  return os.date("%m/%d %H:%M", ts_sec)
end

local function relative_path(filepath, base)
  if not filepath or not base then
    return filepath
  end
  if base:sub(-1) ~= "/" then
    base = base .. "/"
  end
  if filepath:sub(1, #base) == base then
    return filepath:sub(#base + 1)
  end
  return filepath
end

local function build_tree(cwd)
  local sessions = session_index.list_sessions(cwd)
  local root = {
    id = "claude_sessions_root",
    name = "Claude Sessions",
    type = "directory",
    loaded = true,
    children = {},
  }

  for _, session in ipairs(sessions) do
    local date = format_date(session.last_ts)
    local changes = session_index.get_changes(session.id)
    local session_node = {
      id = "session:" .. session.id,
      name = string.format("[%s] %s", date, session.summary),
      type = "session",
      extra = {
        session_id = session.id,
      },
      children = #changes > 0 and {} or nil,
      loaded = true,
    }

    for i, change in ipairs(changes) do
      local display_name = relative_path(change.path, cwd)
      local child = {
        id = "change:" .. session.id .. ":" .. i .. ":" .. change.path,
        name = display_name,
        type = "file",
        path = change.path,
        extra = { session_id = session.id, change = change },
      }
      session_node.children[#session_node.children + 1] = child
    end

    root.children[#root.children + 1] = session_node
  end

  return { root }
end

M.navigate = function(state, _path, _path_to_reveal, callback, _async)
  state.loading = true
  local cwd = vim.fn.getcwd()
  local items = build_tree(cwd)
  state.default_expanded_nodes = { "claude_sessions_root" }

  renderer.show_nodes(items, state)
  if state.enable_source_selector == false and vim.api.nvim_win_is_valid(state.winid) then
    vim.wo[state.winid].winbar = ""
    vim.wo[state.winid].statusline = ""
  end
  state.loading = false

  if callback then
    callback()
  end
end

M.setup = function(_config, _global_config)
  -- No events to register
end

return M
