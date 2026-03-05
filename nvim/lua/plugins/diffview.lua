return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory" },
  config = function()
    require("diffview").setup({
      enhanced_diff_hl = true,
      view = {
        default = { layout = "diff2_horizontal" },
      },
      file_panel = {
        listing_style = "tree",
        win_config = { width = 35 },
      },
    })
  end,
  keys = {
    {
      "<leader>gd",
      function()
        local layout = vim.o.columns >= 160 and "diff2_horizontal" or "diff2_vertical"
        vim.cmd("DiffviewOpen -layout=" .. layout)
      end,
      desc = "差分ビュー (全体)",
    },
    { "<leader>gD", "<cmd>DiffviewClose<CR>", desc = "差分ビューを閉じる" },
    { "<leader>gh", "<cmd>DiffviewFileHistory %<CR>", desc = "ファイル履歴" },
  },
}
