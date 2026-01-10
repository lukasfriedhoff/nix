local function safe_require(module)
  local ok, mod = pcall(require, module)
  if not ok then
    return nil
  end
  return mod
end

local function get_visual_selection()
  local saved_reg = vim.fn.getreg('"')
  local saved_type = vim.fn.getregtype('"')
  vim.cmd('noautocmd normal! ""y')
  local selection = vim.fn.getreg('"')
  vim.fn.setreg('"', saved_reg, saved_type)
  return selection
end

local function open_floating_buffer(title, body)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('filetype', 'markdown', { buf = buf })
  vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

  local lines = vim.split(vim.trim(body), '\n', { plain = true, trimempty = true })
  if vim.tbl_isempty(lines) then
    lines = { '(no output)' }
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  local width = math.floor(vim.o.columns * 0.6)
  local height = math.floor(vim.o.lines * 0.6)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    border = 'rounded',
    title = title,
    title_pos = 'center',
  })
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

-- Colorscheme
local tokyonight = safe_require("tokyonight")
if tokyonight then
  vim.cmd.colorscheme("tokyonight-night")
end

-- Treesitter & Telescope
local treesitter = safe_require("nvim-treesitter.configs")
if treesitter then
  treesitter.setup({
    highlight = { enable = true },
    indent = { enable = true },
  })
end

local telescope_builtin = safe_require("telescope.builtin")
if telescope_builtin then
  vim.keymap.set("n", "<leader>ff", telescope_builtin.find_files, { desc = "Find Files" })
  vim.keymap.set("n", "<leader>fg", telescope_builtin.live_grep, { desc = "Ripgrep" })
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

-- Mason / LSP
local mason = safe_require("mason")
local mason_lspconfig = safe_require("mason-lspconfig")
local lspconfig = safe_require("lspconfig")
if mason and mason_lspconfig and lspconfig then
  mason.setup()
  mason_lspconfig.setup({
    ensure_installed = { "lua_ls", "bashls", "yamlls", "jsonls", "gopls", "tsserver", "pyright" },
  })

  local cmp_nvim_lsp = safe_require("cmp_nvim_lsp")
  local capabilities = cmp_nvim_lsp and cmp_nvim_lsp.default_capabilities() or nil

  local servers = { "lua_ls", "bashls", "yamlls", "jsonls", "gopls", "tsserver", "pyright" }
  for _, server in ipairs(servers) do
    local opts = {}
    if capabilities then
      opts.capabilities = capabilities
    end
    if server == "lua_ls" then
      opts.settings = {
        Lua = {
          diagnostics = { globals = { "vim" } },
          workspace = { checkThirdParty = false },
        },
      }
    end
    lspconfig[server].setup(opts)
  end
end

-- Completion setup
local cmp = safe_require("cmp")
local luasnip = safe_require("luasnip")
if cmp and luasnip then
  cmp.setup({
    snippet = {
      expand = function(args)
        luasnip.lsp_expand(args.body)
      end,
    },
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
end

-- Copilot integration (optional)
local copilot = safe_require("copilot")
if copilot then
  copilot.setup({
    suggestion = { enabled = true },
    panel = { enabled = true },
  })
end

local copilot_chat = safe_require("CopilotChat")
if copilot_chat then
  copilot_chat.setup({})
  vim.keymap.set("n", "<leader>cc", function()
    copilot_chat.toggle()
  end, { desc = "Copilot Chat" })
end

local chatgpt = safe_require("chatgpt")
if chatgpt then
  chatgpt.setup()
  vim.keymap.set("n", "<leader>co", "<cmd>ChatGPT<CR>", { desc = "Codex / ChatGPT" })
  vim.keymap.set("v", "<leader>ci", "<cmd>ChatGPTEditWithInstruction<CR>", { desc = "Edit with instruction" })
end

-- Codex AI helpers
if vim.fn.executable("codex") == 1 then
  local function run_codex(prompt)
    local output = vim.fn.system({ "codex", "--plain", prompt })
    if vim.v.shell_error ~= 0 then
      vim.notify("Codex error: " .. output, vim.log.levels.ERROR)
      return nil
    end
    return output
  end

  local function ask_codex(prompt, title)
    local reply = run_codex(prompt)
    if not reply then
      return
    end
    open_floating_buffer(title or "Codex", reply)
  end

  vim.api.nvim_create_user_command("Codex", function(opts)
    local prompt = table.concat(opts.fargs, " ")
    if prompt == "" then
      prompt = vim.fn.input("Codex prompt: ")
    end
    if prompt == "" then
      return
    end
    ask_codex(prompt, "Codex")
  end, { nargs = "*" })

  vim.api.nvim_create_user_command("CodexTerminal", function()
    vim.cmd("tabnew | terminal codex")
  end, { desc = "Launch interactive Codex terminal" })

  vim.keymap.set("n", "<leader>ca", function()
    local prompt = vim.fn.input("Codex prompt: ")
    if prompt == "" then
      return
    end
    ask_codex(prompt, "Codex prompt")
  end, { desc = "Codex ask" })

  vim.keymap.set("v", "<leader>ca", function()
    local selection = get_visual_selection()
    if selection == "" then
      return
    end
    local prompt = "Explain the following code and include actionable suggestions:\n\n" .. selection
    ask_codex(prompt, "Codex • selection")
  end, { desc = "Codex explain selection" })

  vim.keymap.set("n", "<leader>cT", ":CodexTerminal<CR>", { desc = "Codex terminal" })
end

-- General settings
vim.o.number = true
vim.o.relativenumber = false
vim.o.termguicolors = true
vim.o.cursorline = true
vim.o.signcolumn = "yes"
vim.opt.undofile = true
vim.opt.clipboard = "unnamedplus"

vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, { desc = "Line diagnostics" })
