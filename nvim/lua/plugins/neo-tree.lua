return {
  "nvim-neo-tree/neo-tree.nvim",
  branch = "v3.x",
  lazy = false,
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
    sources = { "filesystem", "buffers", "git_status", "claude_sessions" },
    source_selector = {
      winbar = true,
      sources = {
        { source = "filesystem", display_name = " Files" },
        { source = "claude_sessions", display_name = " Claude" },
        { source = "git_status", display_name = "󰊢 Git" },
      },
    },
    filesystem = {
      follow_current_file = { enabled = true },
      -- WSL2ではlibuv file watcherが重いため無効化
      use_libuv_file_watcher = not (vim.fn.has("wsl") == 1
        or ((vim.uv or vim.loop).os_uname().release or ""):lower():find("microsoft", 1, true)),
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
    claude_sessions = {
      window = {
        mappings = {
          ["<CR>"] = "resume_session",
          ["d"] = "view_diff",
          ["r"] = "refresh",
        },
      },
    },
  },
}
