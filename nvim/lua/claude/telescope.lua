local index = require("claude.session_index")
local map = vim.keymap.set

local M = {}

local function format_date(ts_ms)
  local ts_sec = math.floor(ts_ms / 1000)
  return os.date("%m/%d %H:%M", ts_sec)
end

function M.sessions(opts)
  local ok_tel, _ = pcall(require, "telescope")
  if not ok_tel then
    vim.notify("telescope.nvim is required", vim.log.levels.ERROR)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local previewers = require("telescope.previewers")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  opts = opts or {}
  local sessions = index.list_sessions(vim.fn.getcwd())

  pickers
    .new(opts, {
      prompt_title = "Claude Sessions",
      finder = finders.new_table({
        results = sessions,
        entry_maker = function(session)
          local date = format_date(session.last_ts)
          return {
            value = session,
            display = string.format("[%s] msgs:%d  %s", date, session.msg_count, session.summary),
            ordinal = session.summary .. " " .. session.id,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      previewer = previewers.new_buffer_previewer({
        define_preview = function(self, entry)
          local changes = index.get_changes(entry.value.id)
          local lines = { "# Changed Files", "" }
          for _, c in ipairs(changes) do
            local icon = c.kind == "create" and "+" or "~"
            lines[#lines + 1] = string.format("  %s  %s", icon, c.path)
          end
          if #changes == 0 then
            lines[#lines + 1] = "  (no file changes)"
          end
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
          vim.bo[self.state.bufnr].filetype = "markdown"
        end,
      }),
      attach_mappings = function(prompt_bufnr, pmap)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          if entry then
            require("ui.claude_float").resume(entry.value.id)
          end
        end)

        pmap("i", "<C-d>", function()
          actions.close(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          if entry then
            local ok, diff = pcall(require, "claude.diff")
            if ok then
              diff.show(entry.value.id)
            end
          end
        end)

        pmap("i", "<C-x>", function()
          local entry = action_state.get_selected_entry()
          if entry then
            local changes = index.get_changes(entry.value.id)
            local qf_items = {}
            for _, c in ipairs(changes) do
              qf_items[#qf_items + 1] = {
                filename = c.path,
                text = c.kind,
              }
            end
            vim.fn.setqflist(qf_items, "r")
            actions.close(prompt_bufnr)
            vim.cmd("copen")
          end
        end)

        return true
      end,
    })
    :find()
end

function M.prompts(opts)
  local ok_tel, _ = pcall(require, "telescope")
  if not ok_tel then
    vim.notify("telescope.nvim is required", vim.log.levels.ERROR)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  opts = opts or {}
  local sessions = index.list_sessions(vim.fn.getcwd())

  pickers
    .new(opts, {
      prompt_title = "Claude Prompts",
      finder = finders.new_table({
        results = sessions,
        entry_maker = function(session)
          local date = format_date(session.last_ts)
          return {
            value = session,
            display = string.format("[%s] %s", date, session.summary),
            ordinal = session.summary,
          }
        end,
      }),
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local entry = action_state.get_selected_entry()
          if entry then
            require("ui.claude_float").resume(entry.value.id)
          end
        end)
        return true
      end,
    })
    :find()
end

map("n", "<leader>cs", function()
  M.sessions()
end, { desc = "Claude セッション検索" })
map("n", "<leader>cp", function()
  M.prompts()
end, { desc = "Claude プロンプト検索" })

return M
