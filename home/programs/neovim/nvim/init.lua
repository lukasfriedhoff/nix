-- bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git","clone","--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  -- UI/ergonomics
  { "nvim-lualine/lualine.nvim", config = function() require("lualine").setup() end },
  { "lewis6991/gitsigns.nvim", config = true },
  { "folke/which-key.nvim", config = true },
  { "nvim-tree/nvim-web-devicons" },
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate" },
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" } },

  -- LSP + completion
  { "williamboman/mason.nvim", config = true },
  { "williamboman/mason-lspconfig.nvim" },
  { "neovim/nvim-lspconfig" },
  { "hrsh7th/nvim-cmp" },
  { "hrsh7th/cmp-nvim-lsp" },
  { "L3MON4D3/LuaSnip" },
  { "saadparwaiz1/cmp_luasnip" },

  { "echasnovski/mini.nvim", version = "*" },
  -- === AI OPTIONS (choose what you like) ===

  -- A) GitHub Copilot + CopilotChat
  { "zbirenbaum/copilot.lua",
    cmd = "Copilot",
    event = "InsertEnter",
    config = function()
      require("copilot").setup({ suggestion = { enabled = true }, panel = { enabled = true } })
    end
  },
  { "CopilotC-Nvim/CopilotChat.nvim",
    dependencies = { "zbirenbaum/copilot.lua", "nvim-lua/plenary.nvim" },
    build = "make",
    opts = {}
  },

  -- B) ChatGPT.nvim (OpenAI)
  { "jackMort/ChatGPT.nvim",
    dependencies = { "nvim-lua/plenary.nvim","MunifTanjim/nui.nvim","nvim-telescope/telescope.nvim" },
    config = function() require("chatgpt").setup() end
  },
})

-- Treesitter & Telescope basics
require("nvim-treesitter.configs").setup({ highlight = { enable = true }, indent = { enable = true } })
vim.keymap.set("n","<leader>ff", require("telescope.builtin").find_files, { desc="Find Files" })
vim.keymap.set("n","<leader>fg", require("telescope.builtin").live_grep,  { desc="Grep" })

-- LSP + completion wiring
local cmp = require("cmp")
local luasnip = require("luasnip")
cmp.setup({
  snippet = { expand = function(args) luasnip.lsp_expand(args.body) end },
  mapping = cmp.mapping.preset.insert({
    ["<CR>"] = cmp.mapping.confirm({ select = true }),
    ["<C-Space>"] = cmp.mapping.complete(),
  }),
  sources = { {name="nvim_lsp"}, {name="luasnip"} }
})

require("mason-lspconfig").setup({
  ensure_installed = { "lua_ls", "bashls", "yamlls", "jsonls", "gopls", "ts_ls", "pyright" }
})
local lspcfg = require("lspconfig")
local capabilities = require("cmp_nvim_lsp").default_capabilities()
for _,server in ipairs({ "lua_ls","bashls","yamlls","jsonls","gopls","ts_ls","pyright" }) do
  lspcfg[server].setup({ capabilities = capabilities })
end

-- quality-of-life
vim.o.number = true
vim.o.relativenumber = true
vim.o.termguicolors = true
vim.keymap.set("n","<leader>e", vim.diagnostic.open_float, { desc="Line diagnostics" })

-- CopilotChat shortcuts (if you enabled it)
vim.keymap.set("n", "<leader>cc", "<cmd>CopilotChat<cr>", { desc = "Copilot Chat" })
vim.keymap.set("v", "<leader>ce", "<cmd>CopilotChatExplain<cr>", { desc = "Explain code" })
