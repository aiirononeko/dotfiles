local uv = vim.uv or vim.loop

local M = {}

local timer = nil
local tracked_mtimes = {}
local setup_done = false

local POLL_INTERVAL_MS = 2000

local function stat_mtime_sec(path)
  local stat = uv.fs_stat(path)
  if not stat or not stat.mtime then
    return nil
  end
  return stat.mtime.sec or stat.mtime.tv_sec or 0
end

local function on_external_change(bufnr, path)
  vim.cmd("checktime " .. bufnr)

  local filename = vim.fn.fnamemodify(path, ":t")
  vim.notify(" " .. filename .. " が外部で変更されました", vim.log.levels.INFO)

  pcall(function()
    require("gitsigns").refresh()
  end)
end

local function check_changes()
  local ok, float = pcall(require, "ui.claude_float")
  if not ok or not float.is_active() then
    return
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local path = vim.api.nvim_buf_get_name(bufnr)
      if path ~= "" then
        local mtime = stat_mtime_sec(path)
        if mtime then
          local prev = tracked_mtimes[path]
          if prev and mtime > prev then
            vim.schedule(function()
              if vim.api.nvim_buf_is_valid(bufnr) then
                on_external_change(bufnr, path)
              end
            end)
          end
          tracked_mtimes[path] = mtime
        end
      end
    end
  end
end

function M.start()
  if timer then
    return
  end

  if not setup_done then
    M.setup()
  end

  timer = uv.new_timer()
  timer:start(POLL_INTERVAL_MS, POLL_INTERVAL_MS, vim.schedule_wrap(check_changes))
end

function M.stop()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
  tracked_mtimes = {}
end

function M.setup()
  if setup_done then
    return
  end
  setup_done = true

  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.stop()
    end,
  })

  -- Auto-start watcher
  M.start()
end

return M
