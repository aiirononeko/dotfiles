-- lazy.nvim のブートストラップ
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = {},
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-tree/nvim-web-devicons",
      "MunifTanjim/nui.nvim",
    },
    keys = {
      { "<leader>e", "<cmd>Neotree toggle<CR>", desc = "ファイルツリー切替" },
    },
    opts = {
      close_if_last_window = true,
      filesystem = {
        follow_current_file = { enabled = true },
        use_libuv_file_watcher = true,
        filtered_items = {
          hide_dotfiles = false,
          hide_gitignored = false,
        },
      },
      window = {
        width = 30,
        mappings = {
          ["<space>"] = "none",
        },
      },
      default_component_configs = {
        indent = {
          with_expanders = true,
        },
        git_status = {
          symbols = {
            added     = "",
            modified  = "",
            deleted   = "",
            renamed   = "➜",
            untracked = "★",
            ignored   = "◌",
            unstaged  = "✗",
            staged    = "✓",
            conflict  = "",
          },
        },
      },
    },
  },
  {
    "echasnovski/mini.pick",
    version = false,
    keys = {
      { "<leader>f", function() require("mini.pick").builtin.files() end, desc = "ファイル検索" },
      { "<leader>g", function() require("mini.pick").builtin.grep_live() end, desc = "テキスト検索" },
      { "<leader>b", function() require("mini.pick").builtin.buffers() end, desc = "バッファ一覧" },
    },
    opts = {
      window = {
        config = function()
          local height = math.floor(0.6 * vim.o.lines)
          local width = math.floor(0.6 * vim.o.columns)
          return {
            anchor = "NW",
            height = height,
            width = width,
            row = math.floor(0.5 * (vim.o.lines - height)),
            col = math.floor(0.5 * (vim.o.columns - width)),
            border = "rounded",
          }
        end,
      },
    },
  },
  {
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
  },
  {
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
  },
  {
    "kdheepak/lazygit.nvim",
    cmd = { "LazyGit" },
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>gg", "<cmd>LazyGit<CR>", desc = "LazyGit" },
    },
  },
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "storm",
      transparent = true,
      styles = {
        sidebars = "transparent",
        floats = "transparent",
      },
    },
    config = function(_, opts)
      require("tokyonight").setup(opts)
      vim.cmd.colorscheme("tokyonight")
    end,
  },
})
