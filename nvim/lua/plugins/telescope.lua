return {
  "nvim-telescope/telescope.nvim",
  cmd = "Telescope",
  dependencies = { "nvim-lua/plenary.nvim" },
  keys = {
    { "<leader>f", "<cmd>Telescope find_files<CR>", desc = "ファイル検索" },
    { "<leader>g", "<cmd>Telescope live_grep<CR>", desc = "テキスト検索" },
    { "<leader>b", "<cmd>Telescope buffers<CR>", desc = "バッファ一覧" },
  },
  config = function()
    local telescope = require("telescope")
    local actions = require("telescope.actions")

    telescope.setup({
      defaults = {
        layout_config = {
          horizontal = {
            width = 0.7,
            height = 0.7,
            preview_width = 0.5,
          },
        },
        borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
        sorting_strategy = "ascending",
        layout_strategy = "horizontal",
        prompt_prefix = "  ",
        selection_caret = " ",
        mappings = {
          i = {
            -- <Esc>/jj でノーマルモードに入れるようにする
            ["<Esc>"] = false,
          },
          n = {
            ["j"] = actions.move_selection_next,
            ["k"] = actions.move_selection_previous,
            ["q"] = actions.close,
            ["<Esc>"] = actions.close,
          },
        },
      },
      pickers = {
        find_files = {
          hidden = true,
        },
      },
    })
  end,
}
