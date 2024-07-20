return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    filesystem = {
      filtered_items = {
        visible = true,
        show_hidden_count = true,
        hide_dotfiles = false,
        hide_gitignored = true,
        hide_by_name = {
          -- '.git',
          ".DS_Store",
          -- 'thumbs.db',
        },
        never_show = {},
      },
    },
    window = {
      width = function()
        local columns = vim.o.columns
        if columns < 160 then
          -- 小さな画面用（13インチラップトップを想定）
          return math.max(35, math.min(70, math.floor(columns * 0.25)))
        else
          -- 大きな画面用（27インチモニターを想定）
          return math.max(50, math.min(100, math.floor(columns * 0.25)))
        end
      end,
    },
  },
}
