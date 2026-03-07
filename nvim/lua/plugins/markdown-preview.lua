return {
  "OXY2DEV/markview.nvim",
  lazy = false,
  config = function()
    require("markview").setup({
      preview = {
        enable = true,
        enable_hybrid_mode = true,
        filetypes = { "markdown" },
        ignore_buftypes = { "nofile" },
        icon_provider = "internal",
      },
    })

    vim.keymap.set("n", "<leader>mt", "<cmd>Markview<CR>", { desc = "Markview toggle" })
    vim.keymap.set("n", "<leader>ms", "<cmd>Markview splitToggle<CR>", { desc = "Markview split view" })
  end,
}
