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
