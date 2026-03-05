local startup_group = vim.api.nvim_create_augroup("CoreStartup", { clear = true })

-- 起動時: 常にファイルツリーを開いてフォーカス
vim.api.nvim_create_autocmd("VimEnter", {
  group = startup_group,
  once = true,
  callback = function()
    -- ファイル引数がある場合はツリーを自動で開かない
    if vim.fn.argc() > 0 then return end

    vim.schedule(function()
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
