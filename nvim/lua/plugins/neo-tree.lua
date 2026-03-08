local function git_pull()
  local events = require("neo-tree.events")
  local popups = require("neo-tree.ui.popups")
  local result = vim.fn.systemlist({ "git", "pull" })

  if vim.v.shell_error ~= 0 then
    popups.alert("ERROR: git pull", result)
    return
  end

  events.fire_event(events.GIT_EVENT)
  popups.alert("git pull", result)
end

local function git_toggle_stage(state)
  local events = require("neo-tree.events")
  local git = require("neo-tree.git")
  local popups = require("neo-tree.ui.popups")
  local node = assert(state.tree:get_node())

  if node.type == "message" then
    return
  end

  local path = node:get_id()
  local worktree_root = git.find_existing_worktree(path)
  if not worktree_root then
    return
  end

  local relative_path = path == worktree_root and "." or path:sub(#worktree_root + 2)
  local status =
    vim.fn.systemlist({ "git", "-C", worktree_root, "status", "--porcelain=v1", "--", relative_path })
  if vim.v.shell_error ~= 0 then
    popups.alert("ERROR: git status", status)
    return
  end
  if #status == 0 then
    return
  end

  local has_unstaged = false
  for _, line in ipairs(status) do
    local worktree_status = line:sub(2, 2)
    if worktree_status ~= "" and worktree_status ~= " " then
      has_unstaged = true
      break
    end
  end

  local cmd = has_unstaged
      and { "git", "-C", worktree_root, "add", "--", relative_path }
    or { "git", "-C", worktree_root, "reset", "--", relative_path }
  local result = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    popups.alert("ERROR: " .. table.concat(cmd, " "), result)
    return
  end

  events.fire_event(events.GIT_EVENT)
end

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
    {
      "<leader>cs",
      function()
        require("ui.claude_sessions_tree").toggle()
      end,
      desc = "Claude セッション一覧",
    },
  },
  opts = {
    close_if_last_window = true,
    sources = { "filesystem", "buffers", "git_status", "claude_sessions" },
    source_selector = {
      winbar = true,
      sources = {
        { source = "filesystem", display_name = " Files" },
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
        position = "float",
        popup = {
          title = " Claude Sessions ",
          size = {
            width = "48%",
            height = "72%",
          },
          position = "50%",
          border = "rounded",
        },
        mappings = {
          ["<cr>"] = "open_or_toggle",
          ["<"] = "none",
          [">"] = "none",
          ["o"] = "open_file",
          ["R"] = "resume_session",
          ["d"] = "view_diff",
          ["r"] = "refresh",
        },
      },
    },
    git_status = {
      commands = {
        git_pull = git_pull,
        git_toggle_stage = git_toggle_stage,
      },
      window = {
        mappings = {
          ["a"] = "git_toggle_stage",
          ["c"] = "git_commit",
          ["p"] = "git_pull",
          ["P"] = "git_push",
        },
      },
    },
  },
  config = function(_, opts)
    local neo_tree = require("neo-tree")

    neo_tree.setup(opts)
    neo_tree.ensure_config()
    require("ui.claude_sessions_tree").setup()
  end,
}
