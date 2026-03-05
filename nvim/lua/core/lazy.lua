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
    "echasnovski/mini.pick",
    version = false,
    keys = {
      { "<leader>f", function() require("mini.pick").builtin.files() end, desc = "Find files" },
      { "<leader>g", function() require("mini.pick").builtin.grep_live() end, desc = "Live grep" },
      { "<leader>b", function() require("mini.pick").builtin.buffers() end, desc = "Find buffers" },
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
