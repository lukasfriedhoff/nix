local function safe_require(module)
  local ok, mod = pcall(require, module)
  if not ok then
    return nil
  end
  return mod
end

-- General settings
vim.o.number = true
vim.o.relativenumber = false
vim.o.termguicolors = true
vim.o.cursorline = true
vim.o.signcolumn = "yes"
vim.opt.undofile = true
vim.opt.clipboard = "unnamedplus"
vim.o.autoread = true
vim.o.updatetime = 250
vim.o.timeoutlen = 300
vim.o.completeopt = "menu,menuone,noselect"
vim.o.equalalways = false
if vim.fn.exists("&splitkeep") == 1 then
  vim.o.splitkeep = "screen"
end

-- UI / ergonomics
local lualine = safe_require("lualine")
if lualine then
  lualine.setup()
end

local gitsigns = safe_require("gitsigns")
if gitsigns then
  gitsigns.setup()
end

local which_key = safe_require("which-key")
if which_key then
  which_key.setup()
end

local notify = safe_require("notify")
if notify then
  vim.notify = notify
end

local snacks = safe_require("snacks")
if snacks then
  snacks.setup({
    input = { enabled = true },
    picker = { enabled = true },
    terminal = { enabled = true },
  })
end

-- Colorscheme
local tokyonight = safe_require("tokyonight")
if tokyonight then
  vim.cmd.colorscheme("tokyonight-night")
end

-- Treesitter
local treesitter = safe_require("nvim-treesitter.configs")
if treesitter then
  treesitter.setup({
    highlight = { enable = true },
    indent = { enable = true },
    ensure_installed = {
      "bash",
      "c",
      "go",
      "gomod",
      "gosum",
      "hcl",
      "javascript",
      "json",
      "lua",
      "markdown",
      "nix",
      "python",
      "terraform",
      "typescript",
      "tsx",
      "yaml",
      "helm",
    },
    textobjects = {
      select = {
        enable = true,
        lookahead = true,
        keymaps = {
          ["af"] = "@function.outer",
          ["if"] = "@function.inner",
          ["ac"] = "@class.outer",
          ["ic"] = "@class.inner",
        },
      },
    },
  })
end

-- Telescope
local telescope_builtin = safe_require("telescope.builtin")
if telescope_builtin then
  vim.keymap.set("n", "<leader>ff", telescope_builtin.find_files, { desc = "Find Files" })
  vim.keymap.set("n", "<leader>fg", telescope_builtin.live_grep, { desc = "Live Grep" })
  vim.keymap.set("n", "<leader>fb", telescope_builtin.buffers, { desc = "Buffers" })
  vim.keymap.set("n", "<leader>fh", telescope_builtin.help_tags, { desc = "Help Tags" })
  vim.keymap.set("n", "<leader>fd", telescope_builtin.diagnostics, { desc = "Diagnostics" })
  vim.keymap.set("n", "<leader>fs", telescope_builtin.lsp_document_symbols, { desc = "Document Symbols" })
end

-- File tree
local nvim_tree = safe_require("nvim-tree")
if nvim_tree then
  nvim_tree.setup({
    view = { width = 35 },
    renderer = {
      highlight_git = true,
      icons = { show = { git = true, folder = true, file = true } },
    },
    filters = { dotfiles = false },
  })
  vim.keymap.set("n", "<leader>t", ":NvimTreeToggle<CR>", { desc = "Toggle file tree" })
end

-- Lazygit
local lazygit_ok = pcall(require, "lazygit")
if lazygit_ok then
  vim.keymap.set("n", "<leader>gg", "<cmd>LazyGit<CR>", { desc = "LazyGit" })

  -- Keep lazygit usable inside terminal buffers:
  -- 1) Always re-enter terminal input mode when focusing lazygit.
  -- 2) Send <Esc> to lazygit itself (use <C-\\><C-n> to leave terminal mode).
  local lazygit_group = vim.api.nvim_create_augroup("LazygitTerminalFixes", { clear = true })
  vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter" }, {
    group = lazygit_group,
    pattern = "term://*lazygit*",
    callback = function()
      vim.cmd.startinsert()
      vim.opt_local.number = false
      vim.opt_local.relativenumber = false
      vim.opt_local.cursorline = false
      vim.keymap.set("t", "<Esc>", "<Esc>", { buffer = true, nowait = true, silent = true })
    end,
  })
end

-- LSP configuration
local mason = safe_require("mason")
local mason_lspconfig = safe_require("mason-lspconfig")
local lspconfig = safe_require("lspconfig")
local cmp_nvim_lsp = safe_require("cmp_nvim_lsp")

if mason then
  mason.setup()
end

if mason_lspconfig then
  mason_lspconfig.setup({
    automatic_installation = false,
  })
end

local capabilities = nil
if cmp_nvim_lsp then
  capabilities = cmp_nvim_lsp.default_capabilities()
end

local on_attach = function(_, bufnr)
  local opts = { buffer = bufnr }
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
  vim.keymap.set("n", "gD", vim.lsp.buf.declaration, vim.tbl_extend("force", opts, { desc = "Go to declaration" }))
  vim.keymap.set("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "References" }))
  vim.keymap.set("n", "gi", vim.lsp.buf.implementation, vim.tbl_extend("force", opts, { desc = "Implementation" }))
  vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover" }))
  vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename" }))
  vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", opts, { desc = "Code action" }))
  vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, vim.tbl_extend("force", opts, { desc = "Line diagnostics" }))
  vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, vim.tbl_extend("force", opts, { desc = "Previous diagnostic" }))
  vim.keymap.set("n", "]d", vim.diagnostic.goto_next, vim.tbl_extend("force", opts, { desc = "Next diagnostic" }))
end

-- Neovim 0.11+ uses vim.lsp.config/vim.lsp.enable
local use_builtin_lsp = type(vim.lsp) == "table" and vim.lsp.config ~= nil and type(vim.lsp.enable) == "function"

local servers = {
  lua_ls = {
    settings = {
      Lua = {
        diagnostics = { globals = { "vim" } },
        workspace = { checkThirdParty = false },
        telemetry = { enable = false },
      },
    },
  },
  bashls = {},
  yamlls = {
    settings = {
      yaml = {
        schemas = {
          kubernetes = "*.k8s.yaml",
          ["https://json.schemastore.org/github-workflow.json"] = ".github/workflows/*.yml",
          ["https://json.schemastore.org/kustomization.json"] = "kustomization.yaml",
        },
        validate = true,
        completion = true,
      },
    },
  },
  jsonls = {},
  gopls = {
    settings = {
      gopls = {
        analyses = {
          unusedparams = true,
          shadow = true,
        },
        staticcheck = true,
        gofumpt = true,
      },
    },
  },
  ts_ls = {},
  pyright = {},
  clangd = {},
  terraformls = {},
  tflint = {},
  -- ansiblels removed from nixpkgs; use ansible-lint via none-ls instead
  helm_ls = {
    settings = {
      ["helm-ls"] = {
        yamlls = {
          path = "yaml-language-server",
        },
      },
    },
  },
}

if lspconfig then
  for server, config in pairs(servers) do
    local opts = vim.tbl_deep_extend("force", {
      capabilities = capabilities,
      on_attach = on_attach,
    }, config)

    if use_builtin_lsp then
      vim.lsp.config(server, opts)
      vim.lsp.enable(server)
    elseif lspconfig[server] then
      lspconfig[server].setup(opts)
    end
  end
end

-- Completion setup
local cmp = safe_require("cmp")
local luasnip = safe_require("luasnip")
if cmp and luasnip then
  require("luasnip.loaders.from_vscode").lazy_load()

  cmp.setup({
    snippet = {
      expand = function(args)
        luasnip.lsp_expand(args.body)
      end,
    },
    mapping = cmp.mapping.preset.insert({
      ["<C-b>"] = cmp.mapping.scroll_docs(-4),
      ["<C-f>"] = cmp.mapping.scroll_docs(4),
      ["<C-Space>"] = cmp.mapping.complete(),
      ["<C-e>"] = cmp.mapping.abort(),
      ["<CR>"] = cmp.mapping.confirm({ select = true }),
      ["<Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_next_item()
        elseif luasnip.expand_or_jumpable() then
          luasnip.expand_or_jump()
        else
          fallback()
        end
      end, { "i", "s" }),
      ["<S-Tab>"] = cmp.mapping(function(fallback)
        if cmp.visible() then
          cmp.select_prev_item()
        elseif luasnip.jumpable(-1) then
          luasnip.jump(-1)
        else
          fallback()
        end
      end, { "i", "s" }),
    }),
    sources = cmp.config.sources({
      { name = "nvim_lsp" },
      { name = "luasnip" },
    }, {
      { name = "buffer" },
      { name = "path" },
    }),
  })
end

-- Formatting with conform.nvim
local conform = safe_require("conform")
if conform then
  conform.setup({
    formatters_by_ft = {
      lua = { "stylua" },
      python = { "ruff_format", "black" },
      go = { "gofumpt", "goimports" },
      javascript = { "prettier" },
      typescript = { "prettier" },
      javascriptreact = { "prettier" },
      typescriptreact = { "prettier" },
      json = { "prettier" },
      yaml = { "prettier" },
      markdown = { "prettier" },
      bash = { "shfmt" },
      sh = { "shfmt" },
      terraform = { "terraform_fmt" },
      tf = { "terraform_fmt" },
      nix = { "nixfmt" },
      c = { "clang_format" },
      cpp = { "clang_format" },
    },
    format_on_save = function(bufnr)
      -- Disable autoformat for certain filetypes
      local ignore_filetypes = { "helm" }
      if vim.tbl_contains(ignore_filetypes, vim.bo[bufnr].filetype) then
        return
      end
      return { timeout_ms = 500, lsp_fallback = true }
    end,
  })

  vim.keymap.set({ "n", "v" }, "<leader>cf", function()
    conform.format({ async = true, lsp_fallback = true })
  end, { desc = "Format buffer" })
end

-- Linting with none-ls (null-ls successor)
-- Note: Most builtins were removed in none-ls; only golangci_lint remains.
-- Other linting is handled by LSP servers directly.
local null_ls = safe_require("null-ls")
if null_ls and null_ls.builtins.diagnostics.golangci_lint then
  null_ls.setup({
    sources = {
      null_ls.builtins.diagnostics.golangci_lint,
    },
  })
end

-- Local LLM via Ollama
local ollama = safe_require("ollama")
if ollama then
  local ollama_url = vim.env.NVIM_OLLAMA_URL or vim.env.OLLAMA_HOST or "http://127.0.0.1:11434"
  if not ollama_url:match("^https?://") then
    ollama_url = "http://" .. ollama_url
  end

  ollama.setup({
    model = vim.env.NVIM_OLLAMA_MODEL or "llama3.2",
    url = ollama_url,
    prompts = {
      Ask_About_Code = {
        prompt = "I have a question about this: $input\n\nHere is the code:\n```$ftype\n$buf\n```",
        input_label = "Q",
      },
      Explain_Code = {
        prompt = "Explain this code:\n```$ftype\n$buf\n```",
      },
    },
    serve = {
      on_start = false,
    },
  })

  local function ollama_prompt_safe(name)
    local ok, err = pcall(function()
      ollama.prompt(name)
    end)
    if not ok then
      vim.notify(("Ollama prompt failed: %s"):format(tostring(err)), vim.log.levels.ERROR, { title = "Ollama" })
    end
  end

  vim.keymap.set("n", "<leader>lo", function()
    ollama_prompt_safe()
  end, { desc = "Ollama prompt" })
  vim.keymap.set("n", "<leader>lg", function()
    ollama_prompt_safe("Generate_Code")
  end, { desc = "Ollama generate code" })
  vim.keymap.set("n", "<leader>lr", function()
    ollama_prompt_safe("Raw")
  end, { desc = "Ollama raw prompt" })
  vim.keymap.set("x", "<leader>lo", ":<C-u>lua require('ollama').prompt()<CR>", { desc = "Ollama prompt (selection)" })
  vim.keymap.set(
    "x",
    "<leader>lg",
    ":<C-u>lua require('ollama').prompt('Generate_Code')<CR>",
    { desc = "Ollama generate code (selection)" }
  )
  vim.keymap.set("x", "<leader>lr", ":<C-u>lua require('ollama').prompt('Raw')<CR>", { desc = "Ollama raw (selection)" })
  vim.keymap.set("n", "<leader>lm", "<cmd>OllamaModel<CR>", { desc = "Ollama select model" })
end

-- OpenCode IDE integration via opencode.nvim.
-- Keep this on the opencode.nvim API; CodeCompanion ACP renders a separate
-- markdown chat buffer and has been fragile in the current split-heavy layout.
local opencode_config = safe_require("opencode.config")
local opencode = safe_require("opencode")
if opencode and opencode_config then
  local opencode_cmd = "opencode --port"
  local function opencode_width()
    return math.min(96, math.max(48, math.floor(vim.o.columns * 0.38)))
  end
  local function opencode_terminal_opts()
    return {
      split = "right",
      width = opencode_width(),
    }
  end
  local function focus_opencode_terminal()
    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match("term://.*opencode") then
          vim.api.nvim_set_current_win(win)
          vim.cmd.startinsert()
          return
        end
      end
    end)
  end
  local function toggle_opencode()
    opencode.toggle()
    focus_opencode_terminal()
  end

  local opencode_group = vim.api.nvim_create_augroup("OpenCodeTerminalFixes", { clear = true })
  vim.api.nvim_create_autocmd({ "TermOpen", "BufEnter" }, {
    group = opencode_group,
    pattern = "term://*opencode*",
    callback = function()
      vim.cmd.startinsert()
      vim.opt_local.number = false
      vim.opt_local.relativenumber = false
      vim.opt_local.cursorline = false
    end,
  })

  opencode_config.opts.server.start = function()
    require("opencode.terminal").open(opencode_cmd, opencode_terminal_opts())
  end
  opencode_config.opts.server.stop = function()
    require("opencode.terminal").close()
  end
  opencode_config.opts.server.toggle = function()
    require("opencode.terminal").toggle(opencode_cmd, opencode_terminal_opts())
  end

  vim.keymap.set({ "n", "x" }, "<leader>oa", function()
    opencode.ask("@this: ", { submit = true })
  end, { desc = "OpenCode ask about this" })
  vim.keymap.set({ "n", "x" }, "<leader>op", function()
    opencode.ask("@this: ", { submit = false })
  end, { desc = "OpenCode prompt" })
  vim.keymap.set({ "n", "x" }, "<leader>os", function()
    opencode.select()
  end, { desc = "OpenCode select action" })
  vim.keymap.set({ "n", "t" }, "<leader>oc", function()
    toggle_opencode()
  end, { desc = "OpenCode toggle" })
  vim.keymap.set({ "n", "t" }, "<leader>ot", function()
    toggle_opencode()
  end, { desc = "OpenCode toggle" })
  vim.keymap.set("n", "<leader>on", function()
    opencode.command("session.new")
  end, { desc = "OpenCode new session" })
  vim.keymap.set("n", "<leader>ol", function()
    opencode.command("session.select")
  end, { desc = "OpenCode select session" })
  vim.keymap.set("n", "<leader>oi", function()
    opencode.command("session.interrupt")
  end, { desc = "OpenCode interrupt" })
  vim.keymap.set("n", "<leader>ou", function()
    opencode.command("session.half.page.up")
  end, { desc = "OpenCode scroll up" })
  vim.keymap.set("n", "<leader>od", function()
    opencode.command("session.half.page.down")
  end, { desc = "OpenCode scroll down" })
  vim.keymap.set({ "n", "x" }, "<leader>oo", function()
    return opencode.operator("@this ")
  end, { desc = "OpenCode operator", expr = true })
end

-- Kubernetes helpers
vim.api.nvim_create_user_command("K9s", function()
  vim.cmd("tabnew | terminal k9s")
end, { desc = "Launch k9s in terminal" })

vim.keymap.set("n", "<leader>k9", ":K9s<CR>", { desc = "K9s" })
