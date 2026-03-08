local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")

local M = {}

local SOURCE_NAME = "claude_sessions"

M.refresh = utils.wrap(manager.refresh, SOURCE_NAME)

local function get_node(state, node)
  return node or (state and state.tree and state.tree:get_node())
end

local function get_session_id(state, node)
  node = get_node(state, node)
  if not node then
    return nil
  end

  local session_id = node.extra and node.extra.session_id
  if session_id then
    return session_id
  end

  local parent_id = node.get_parent_id and node:get_parent_id() or nil
  if not parent_id or not state or not state.tree then
    return nil
  end

  local parent = state.tree:get_node(parent_id)
  return parent and parent.extra and parent.extra.session_id or nil
end

local function toggle_node(state, node)
  if not node or not node:has_children() then
    return false
  end

  local updated
  if node:is_expanded() then
    updated = node:collapse()
  else
    updated = node:expand()
  end

  if updated then
    renderer.redraw(state)
    renderer.focus_node(state, node:get_id())
  end

  return updated
end

M.open_or_toggle = function(state, node)
  node = get_node(state, node)
  if not node then
    return
  end

  if node.type == "directory" then
    cc.toggle_node(state)
    return
  end

  if node.type == "session" then
    if not toggle_node(state, node) then
      vim.notify("No edited files recorded for this Claude session", vim.log.levels.INFO)
    end
    return
  end

  local change = node.extra and node.extra.change
  if change then
    require("claude.diff").show_change(change, {
      source_win = state.winid,
      focus = false,
      session_id = node.extra.session_id,
    })
  end
end

M.open_file = function(state, node)
  node = get_node(state, node)
  if not node then
    return
  end

  local change = node.extra and node.extra.change
  if change and change.path then
    local diff = require("claude.diff")
    local target_win = diff.find_target_win(state.winid)
    vim.api.nvim_set_current_win(target_win)
    vim.cmd("edit " .. vim.fn.fnameescape(change.path))
  end
end

M.resume_session = function(state, node)
  local session_id = get_session_id(state, node)

  if session_id then
    require("ui.claude_float").resume(session_id)
  end
end

M.view_diff = function(state, node)
  local session_id = get_session_id(state, node)

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
