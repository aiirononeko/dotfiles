local startup_group = vim.api.nvim_create_augroup("CoreStartup", { clear = true })

-- 起動時: 常にファイルツリーを開いてフォーカス
vim.api.nvim_create_autocmd("VimEnter", {
  group = startup_group,
  once = true,
  callback = function()
    vim.schedule(function()
      -- 起動直後でも open_files_in_last_window が正しく効くように現在窓を記録
      local ok, utils = pcall(require, "neo-tree.utils")
      if ok then
        local tabid = vim.api.nvim_get_current_tabpage()
        utils.prior_windows[tabid] = utils.prior_windows[tabid] or {}
        table.insert(utils.prior_windows[tabid], vim.api.nvim_get_current_win())
      end

      vim.cmd("Neotree filesystem focus left")
    end)
  end,
})

-- IME: ノーマルモードでは常に英語入力に切り替え
local uv = vim.uv or vim.loop

local function is_wsl()
  return vim.fn.has("wsl") == 1 or (uv.os_uname().release or ""):lower():find("microsoft", 1, true) ~= nil
end

local function first_available_command(candidates)
  for _, cmd in ipairs(candidates) do
    local bin = cmd[1]
    if vim.fn.executable(bin) == 1 then
      return cmd
    end
  end
  return nil
end

local ime_cmd = nil
if is_wsl() then
  ime_cmd = first_available_command({
    { "zenhan.exe", "0" },
    { vim.fn.expand("~/.local/bin/zenhan.exe"), "0" },
    { "im-select.exe", "1033" },
  })
elseif vim.fn.has("mac") == 1 then
  ime_cmd = first_available_command({
    { "im-select", "com.apple.keylayout.ABC" },
  })
end

if ime_cmd then
  local ime_group = vim.api.nvim_create_augroup("ImeForceEnglish", { clear = true })
  local last_switch_ns = 0
  local min_interval_ns = 120 * 1000000

  local function ime_to_english()
    -- InsertLeave + ModeChanged で連続実行されるのを抑制
    local now = uv.hrtime()
    if now - last_switch_ns < min_interval_ns then
      return
    end
    last_switch_ns = now

    vim.fn.jobstart(ime_cmd, { detach = true })
  end

  vim.api.nvim_create_autocmd({ "InsertLeave", "CmdlineLeave" }, {
    group = ime_group,
    callback = ime_to_english,
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    group = ime_group,
    pattern = "*:n",
    callback = ime_to_english,
  })
end
