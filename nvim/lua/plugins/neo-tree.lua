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

local function git_push()
  local events = require("neo-tree.events")
  local popups = require("neo-tree.ui.popups")
  local choice = vim.fn.confirm("Are you sure you want to push your changes?", "&Yes\n&No", 1)

  if choice ~= 1 then
    return
  end

  local result = vim.fn.systemlist({ "git", "push" })
  if vim.v.shell_error ~= 0 then
    popups.alert("ERROR: git push", result)
    return
  end

  events.fire_event(events.GIT_EVENT)
  popups.alert("git push", result)
end

local AI_COMMIT_TIMEOUT_MS = 15000

local function run_systemlist(cmd)
  local result = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, result
  end

  return result
end

local function commit_with_message(git_root, initial_msg, events, popups)
  vim.ui.input({
    prompt = "Commit Message: ",
    default = initial_msg,
  }, function(input)
    if input == nil then
      return
    end

    local msg = vim.trim(input)
    if msg == "" then
      vim.schedule(function()
        popups.alert("AI Commit", { "Commit canceled: message is empty." })
      end)
      return
    end

    local result = vim.fn.systemlist({ "git", "-C", git_root, "commit", "-m", msg })
    if vim.v.shell_error ~= 0 then
      vim.schedule(function()
        popups.alert("ERROR: git commit", result)
      end)
      return
    end

    vim.schedule(function()
      events.fire_event(events.GIT_EVENT)
      popups.alert("git commit", result)
    end)
  end)
end

local function git_aicommit()
  local events = require("neo-tree.events")
  local popups = require("neo-tree.ui.popups")
  local git_root = run_systemlist({ "git", "rev-parse", "--show-toplevel" })

  if not git_root or git_root[1] == nil or git_root[1] == "" then
    popups.alert("ERROR: AI Commit", { "Failed to detect git root." })
    return
  end

  git_root = git_root[1]

  -- Check if there are staged changes
  vim.fn.system({ "git", "-C", git_root, "diff", "--cached", "--quiet" })
  if vim.v.shell_error == 0 then
    popups.alert("git commit", { "No staged changes." })
    return
  end

  local name_status, name_status_err = run_systemlist({
    "git",
    "-C",
    git_root,
    "diff",
    "--cached",
    "--name-status",
    "--find-renames",
    "--no-ext-diff",
  })
  if not name_status then
    popups.alert("ERROR: AI Commit", name_status_err)
    return
  end

  local diff_stat, diff_stat_err = run_systemlist({
    "git",
    "-C",
    git_root,
    "diff",
    "--cached",
    "--stat=160,120",
    "--summary",
    "--find-renames",
    "--no-ext-diff",
    "--submodule=short",
  })
  if not diff_stat then
    popups.alert("ERROR: AI Commit", diff_stat_err)
    return
  end

  local diff_patch, diff_patch_err = run_systemlist({
    "git",
    "-C",
    git_root,
    "diff",
    "--cached",
    "--unified=0",
    "--minimal",
    "--find-renames",
    "--no-color",
    "--no-ext-diff",
    "--submodule=short",
  })
  if not diff_patch then
    popups.alert("ERROR: AI Commit", diff_patch_err)
    return
  end

  local prompt = table.concat({
    "Generate ONLY a one-line Git commit message in Japanese.",
    "Base it strictly on the staged diff supplied via stdin.",
    "Prefer the actual code changes over filenames.",
    "Do not add quotes, bullets, explanations, or a body.",
    "Output ONLY the commit summary line.",
  }, " ")
  local stdin_payload = table.concat({
    "Staged files (git diff --cached --name-status):",
    table.concat(name_status, "\n"),
    "",
    "Staged summary (git diff --cached --stat --summary):",
    table.concat(diff_stat, "\n"),
    "",
    "Staged patch (git diff --cached --unified=0):",
    table.concat(diff_patch, "\n"),
    "",
  }, "\n")

  popups.alert("AI Commit", { "Generating commit message..." })

  local stdout_chunks = {}
  local stderr_chunks = {}
  local finished = false
  local timed_out = false
  local timer
  local job_id = vim.fn.jobstart({
    "claude",
    "--no-session-persistence",
    "--print",
    "--tools",
    "",
    "--effort",
    "low",
    prompt,
  }, {
    cwd = git_root,
    stdin = "pipe",
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        vim.list_extend(stdout_chunks, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(stderr_chunks, data)
      end
    end,
    on_exit = function(_, code)
      finished = true
      if timer then
        pcall(function()
          timer:stop()
        end)
        pcall(function()
          timer:close()
        end)
      end

      local msg = vim.trim(table.concat(stdout_chunks, "\n"))
      if msg ~= "" then
        msg = vim.split(msg, "\n", { trimempty = true })[1] or ""
        msg = vim.trim(msg:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1"))
      end
      local err = vim.trim(table.concat(stderr_chunks, "\n"))

      vim.schedule(function()
        if timed_out then
          return
        end

        if code ~= 0 then
          popups.alert("ERROR: AI Commit", {
            err ~= "" and err or ("claude exited with status " .. code .. "."),
          })
          return
        end

        if msg == "" then
          popups.alert("ERROR: AI Commit", { "Failed to generate commit message." })
          return
        end

        commit_with_message(git_root, msg, events, popups)
      end)
    end,
  })

  if job_id <= 0 then
    popups.alert("ERROR: AI Commit", { "Failed to start claude." })
    return
  end

  vim.fn.chansend(job_id, stdin_payload)
  vim.fn.chanclose(job_id, "stdin")

  timer = vim.defer_fn(function()
    if finished then
      return
    end

    timed_out = true
    vim.fn.jobstop(job_id)
    vim.schedule(function()
      popups.alert("ERROR: AI Commit", {
        ("Timed out after %ds."):format(AI_COMMIT_TIMEOUT_MS / 1000),
        "Use `mc` for a manual commit if needed.",
      })
    end)
  end, AI_COMMIT_TIMEOUT_MS)
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
        git_push = git_push,
        git_toggle_stage = git_toggle_stage,
        git_aicommit = git_aicommit,
      },
      window = {
        mappings = {
          ["a"] = "git_toggle_stage",
          ["c"] = "git_aicommit",
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
