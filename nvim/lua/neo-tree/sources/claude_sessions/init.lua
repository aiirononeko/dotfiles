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
    file = {
      { "indent" },
      { "icon" },
      { "name" },
    },
  },
  window = {
    mappings = {
      ["<cr>"] = "resume_session",
      ["d"] = "view_diff",
      ["r"] = "refresh",
    },
  },
}

local function format_date(ts_ms)
  local ts_sec = math.floor(ts_ms / 1000)
  return os.date("%m/%d %H:%M", ts_sec)
end

local function build_tree(cwd)
  local sessions = session_index.list_sessions(cwd)
  local root = {
    id = "claude_sessions_root",
    name = "Claude Sessions",
    type = "directory",
    children = {},
  }

  for _, session in ipairs(sessions) do
    local date = format_date(session.last_ts)
    local session_node = {
      id = "session:" .. session.id,
      name = string.format("[%s] %s", date, session.summary),
      type = "directory",
      extra = { session_id = session.id },
      children = {},
      loaded = false,
    }

    local changes = session_index.get_changes(session.id)
    for _, change in ipairs(changes) do
      local child = {
        id = "change:" .. session.id .. ":" .. change.path,
        name = change.path,
        type = "file",
        path = change.path,
        extra = { session_id = session.id, change = change },
      }
      session_node.children[#session_node.children + 1] = child
    end

    session_node.loaded = true
    root.children[#root.children + 1] = session_node
  end

  return { root }
end

M.navigate = function(state, _path, _path_to_reveal, callback, _async)
  state.loading = true
  local cwd = vim.fn.getcwd()
  local items = build_tree(cwd)

  renderer.show_nodes(items, state)
  state.loading = false

  if callback then
    callback()
  end
end

M.setup = function(_config, _global_config)
  -- No events to register
end

return M
