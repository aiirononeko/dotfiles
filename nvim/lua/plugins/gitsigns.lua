return {
  "lewis6991/gitsigns.nvim",
  event = { "BufReadPre", "BufNewFile" },
  opts = {
    signs = {
      add          = { text = "▎" },
      change       = { text = "▎" },
      delete       = { text = "" },
      topdelete    = { text = "" },
      changedelete = { text = "▎" },
      untracked    = { text = "▎" },
    },
    signs_staged = {
      add          = { text = "▎" },
      change       = { text = "▎" },
      delete       = { text = "" },
      topdelete    = { text = "" },
      changedelete = { text = "▎" },
      untracked    = { text = "▎" },
    },
    current_line_blame = false,
    on_attach = function(bufnr)
      local gs = package.loaded.gitsigns
      local function m(mode, l, r, opts)
        opts = opts or {}
        opts.buffer = bufnr
        vim.keymap.set(mode, l, r, opts)
      end
      -- hunkナビゲーション
      m("n", "]c", function()
        if vim.wo.diff then return "]c" end
        vim.schedule(function() gs.next_hunk() end)
        return "<Ignore>"
      end, { expr = true, desc = "次の変更箇所" })
      m("n", "[c", function()
        if vim.wo.diff then return "[c" end
        vim.schedule(function() gs.prev_hunk() end)
        return "<Ignore>"
      end, { expr = true, desc = "前の変更箇所" })
      -- hunk操作
      m("n", "<leader>gr", gs.reset_hunk, { desc = "変更リセット" })
      m("n", "<leader>gb", function() gs.blame_line({ full = true }) end, { desc = "Git Blame" })
    end,
  },
}
