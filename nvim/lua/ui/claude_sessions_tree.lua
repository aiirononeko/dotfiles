local M = {}

local CLAUDE_SOURCE = "claude_sessions"
local function get_config()
  return require("neo-tree").ensure_config()
end

local function get_source_entries()
  local config = get_config()
  local entries = config.source_selector.sources or config.sources or {}
  local normalized = {}

  for _, entry in ipairs(entries) do
    if type(entry) == "string" then
      normalized[#normalized + 1] = { source = entry }
    else
      normalized[#normalized + 1] = entry
    end
  end

  return normalized
end

local function get_source_position(source_name, fallback)
  local config = get_config()
  local source_config = config[source_name] or {}
  local window = source_config.window or {}
  return window.position or fallback or config.window.position or "left"
end

local function close_previous_position(from_position, to_position)
  if not from_position or from_position == to_position or from_position == "current" then
    return
  end

  require("neo-tree.sources.manager").close_all(from_position)
end

local function close_positions(positions)
  local manager = require("neo-tree.sources.manager")

  for _, position in ipairs(positions) do
    manager.close_all(position)
  end
end

function M.focus_source(source_name, opts)
  opts = opts or {}

  local from_position = opts.from_position or (opts.state and opts.state.current_position)
  local target_position = opts.position or get_source_position(source_name, from_position)
  local selector = opts.selector

  if selector == nil and source_name == CLAUDE_SOURCE then
    selector = false
  end

  local function run()
    close_previous_position(from_position, target_position)
    require("neo-tree.command").execute({
      source = source_name,
      position = target_position,
      action = opts.action or "focus",
      selector = selector,
    })
  end

  if opts.schedule == false then
    run()
  else
    vim.schedule(run)
  end
end

function M.toggle()
  local manager = require("neo-tree.sources.manager")
  local renderer = require("neo-tree.ui.renderer")
  local state = manager.get_state(CLAUDE_SOURCE)
  local target_position = get_source_position(CLAUDE_SOURCE, "float")

  if renderer.window_exists(state) then
    if state.current_position == target_position then
      manager.close(CLAUDE_SOURCE)
      return
    end

    manager.close(CLAUDE_SOURCE)
  end

  require("neo-tree.command").execute({
    source = CLAUDE_SOURCE,
    position = target_position,
    action = "focus",
    selector = false,
  })
end

function M.toggle_sidebar()
  local manager = require("neo-tree.sources.manager")
  local renderer = require("neo-tree.ui.renderer")
  local sidebar_position = "left"
  local state = manager.get_state(CLAUDE_SOURCE)

  if renderer.window_exists(state) and state.current_position == sidebar_position then
    manager.close(CLAUDE_SOURCE)
    return
  end

  manager.close(CLAUDE_SOURCE)
  close_positions({ sidebar_position })
  require("neo-tree.command").execute({
    source = CLAUDE_SOURCE,
    position = sidebar_position,
    action = "focus",
    selector = false,
  })
end

local function patch_source_selector()
  local log = require("neo-tree.log")
  local manager = require("neo-tree.sources.manager")

  _G.___neotree_selector_click = function(id, _, _, _)
    if id < 1 then
      return
    end

    local sources = get_source_entries()
    local base_number = #sources + 1
    local winid = math.floor(id / base_number)
    local source_index = id % base_number
    local source_info = sources[source_index]
    if not source_info then
      return
    end

    local state = manager.get_state_for_window(winid)
    if state == nil then
      log.warn("state not found for window ", winid, "; ignoring click")
      return
    end

    M.focus_source(source_info.source, { state = state })
  end
end

local function source_cycler(direction)
  return function(state)
    local sources = get_source_entries()
    local next_source = sources[1]

    for i, source_info in ipairs(sources) do
      if source_info.source == state.name then
        next_source = sources[i + direction]
        if not next_source then
          next_source = direction > 0 and sources[1] or sources[#sources]
        end
        break
      end
    end

    if next_source then
      M.focus_source(next_source.source, { state = state })
    end
  end
end

function M.setup()
  get_config()

  local common_commands = require("neo-tree.sources.common.commands")

  common_commands.next_source = source_cycler(1)
  common_commands.prev_source = source_cycler(-1)

  patch_source_selector()
end

return M
