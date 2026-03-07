local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local manager = require("neo-tree.sources.manager")

local M = {}

local SOURCE_NAME = "claude_sessions"

M.refresh = utils.wrap(manager.refresh, SOURCE_NAME)

M.resume_session = function(state, node)
  node = node or (state and state.tree and state.tree:get_node())
  if not node then
    return
  end

  local session_id = node.extra and node.extra.session_id
  if not session_id then
    -- Try parent node
    local parent = state.tree:get_node(node:get_parent_id())
    if parent and parent.extra then
      session_id = parent.extra.session_id
    end
  end

  if session_id then
    require("ui.claude_float").resume(session_id)
  end
end

M.view_diff = function(state, node)
  node = node or (state and state.tree and state.tree:get_node())
  if not node then
    return
  end

  local session_id = node.extra and node.extra.session_id
  if not session_id then
    local parent = state.tree:get_node(node:get_parent_id())
    if parent and parent.extra then
      session_id = parent.extra.session_id
    end
  end

  if session_id then
    local ok, diff = pcall(require, "claude.diff")
    if ok then
      diff.show(session_id)
    end
  end
end

-- Include common commands
cc._add_common_commands(M)

return M
