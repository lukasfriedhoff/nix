-- =============================
--  Bootstrap lazy.nvim
-- =============================
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath
  })
end
vim.opt.rtp:prepend(lazypath)

-- =============================
--  Plugin setup
-- =============================
require("lazy").setup({
  -- === UI / ergonomics ===
  { "nvim-lualine/lualine.nvim", config = function() require("lualine").setup() end },
  { "lewis6991/gitsigns.nvim", config = true },
  { "folke/which-key.nvim", config = true },
  { "nvim-tree/nvim-web-devicons" },
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },

  -- === File tree ===
  {
    "nvim-tree/nvim-tree.lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    config = function()
      require("nvim-tree").setup({
        view = { width = 35 },
        renderer = {
          highlight_git = true,
          icons = { show = { git = true, folder = true, file = true } },
        },
        filters = { dotfiles = false },
      })
      vim.keymap.set("n", "<leader>t", ":NvimTreeToggle<CR>", { desc = "Toggle file tree" })
    end,
  },

  -- === LSP + completion ===
  { "williamboman/mason.nvim", config = true },
  { "williamboman/mason-lspconfig.nvim" },
  { "neovim/nvim-lspconfig" },
  { "hrsh7th/nvim-cmp" },
  { "hrsh7th/cmp-nvim-lsp" },
  { "L3MON4D3/LuaSnip" },
  { "saadparwaiz1/cmp_luasnip" },

  -- === Colors & polish ===
  {
    "folke/tokyonight.nvim",
    lazy = false,
    priority = 1000,
    config = function() vim.cmd.colorscheme("tokyonight-night") end
  },
  { "rcarriga/nvim-notify", config = function() vim.notify = require("notify") end },

  -- === AI / ChatGPT & Copilot ===
  {
    "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    config = function()
      require("copilot").setup({
        suggestion = { enabled = true },
        panel = { enabled = true },
      })
    end,
  },
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = { "zbirenbaum/copilot.lua", "nvim-lua/plenary.nvim" },
    build = "make",
    opts = {},
  },
  {
    "jackMort/ChatGPT.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-telescope/telescope.nvim"
    },
    config = function() require("chatgpt").setup() end,
  },
})

-- =============================
--  Treesitter & Telescope basics
-- =============================
require("nvim-treesitter.configs").setup({
  highlight = { enable = true },
  indent = { enable = true },
})
vim.keymap.set("n", "<leader>ff", require("telescope.builtin").find_files, { desc = "Find Files" })
vim.keymap.set("n", "<leader>fg", require("telescope.builtin").live_grep, { desc = "Grep" })

-- =============================
--  Completion setup
-- =============================
local cmp = require("cmp")
local luasnip = require("luasnip")
cmp.setup({
  snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
  mapping = cmp.mapping.preset.insert({
    ["<CR>"] = cmp.mapping.confirm({ select = true }),
    ["<C-Space>"] = cmp.mapping.complete(),
    ["<Tab>"] = cmp.mapping.select_next_item(),
    ["<S-Tab>"] = cmp.mapping.select_prev_item(),
  }),
  sources = cmp.config.sources({
    { name = "nvim_lsp" },
    { name = "luasnip" },
  }, {
    { name = "buffer" },
    { name = "path" },
  }),
})

-- =============================
--  LSP Setup (modern API)
-- =============================
require("mason-lspconfig").setup({
  ensure_installed = { "lua_ls", "bashls", "yamlls", "jsonls", "gopls", "tsserver", "pyright" },
})

local capabilities = require("cmp_nvim_lsp").default_capabilities()

vim.lsp.config.lua_ls = {
  capabilities = capabilities,
  settings = {
    Lua = {
      diagnostics = { globals = { "vim" } },
      workspace = { checkThirdParty = false },
    },
  },
}
vim.lsp.config.bashls   = { capabilities = capabilities }
vim.lsp.config.yamlls   = { capabilities = capabilities }
vim.lsp.config.jsonls   = { capabilities = capabilities }
vim.lsp.config.gopls    = { capabilities = capabilities }
vim.lsp.config.tsserver = { capabilities = capabilities }
vim.lsp.config.pyright  = { capabilities = capabilities }

vim.lsp.enable({ "lua_ls", "bashls", "yamlls", "jsonls", "gopls", "tsserver", "pyright" })

-- =============================
--  Quality of life / UI
-- =============================
vim.o.number = true
vim.o.relativenumber = false
vim.o.termguicolors = true
vim.o.cursorline = true
vim.o.signcolumn = "yes"

vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Line diagnostics" })

-- Copilot & ChatGPT mappings
vim.keymap.set("n", "<leader>cc", "<cmd>CopilotChat<cr>", { desc = "Copilot Chat" })
vim.keymap.set("v", "<leader>ce", "<cmd>CopilotChatExplain<cr>", { desc = "Explain code" })
vim.keymap.set("n", "<leader>cg", "<cmd>ChatGPT<CR>", { desc = "Open ChatGPT" })
vim.keymap.set("v", "<leader>ci", "<cmd>ChatGPTEditWithInstruction<CR>", { desc = "Edit with GPT" })

-- Persistent undo & clipboard integration
vim.opt.undofile = true
vim.opt.clipboard = "unnamedplus"