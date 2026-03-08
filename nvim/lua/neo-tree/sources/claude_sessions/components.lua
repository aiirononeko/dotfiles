local highlights = require("neo-tree.ui.highlights")
local common = require("neo-tree.sources.common.components")

local M = {}

M.icon = function(_config, node, _state)
  if node.type == "directory" or node.type == "session" then
    return {
      text = (node:is_expanded() and "" or "") .. " ",
      highlight = highlights.DIRECTORY_ICON,
    }
  end

  local kind = node.extra and node.extra.change and node.extra.change.kind or "edit"

  return {
    text = (kind == "create" and "" or "") .. " ",
    highlight = kind == "create" and "NeoTreeGitAdded" or "NeoTreeGitModified",
  }
end

M.name = function(_config, node, _state)
  return {
    text = node.name,
    highlight = (node.type == "directory" or node.type == "session")
        and highlights.DIRECTORY_NAME
      or highlights.FILE_NAME,
  }
end

return vim.tbl_deep_extend("force", common, M)
