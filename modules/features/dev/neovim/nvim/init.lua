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

local snacks = safe_require("snacks")
if snacks then
  snacks.setup({
    input = { enabled = true },
  })
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
if mason and mason_lspconfig then
  mason.setup()
  mason_lspconfig.setup({
    ensure_installed = { "lua_ls", "bashls", "yamlls", "jsonls", "ts_ls", "pyright" },
  })

  local cmp_nvim_lsp = safe_require("cmp_nvim_lsp")
  local capabilities = cmp_nvim_lsp and cmp_nvim_lsp.default_capabilities() or nil

  local servers = { "lua_ls", "bashls", "yamlls", "jsonls", "gopls", "ts_ls", "pyright" }
  -- Neovim 0.11 exposes vim.lsp.config as a callable table (not a plain function).
  local use_builtin_lsp_config = type(vim.lsp) == "table"
    and vim.lsp.config ~= nil
    and type(vim.lsp.enable) == "function"
  local lspconfig = nil
  if not use_builtin_lsp_config then
    lspconfig = safe_require("lspconfig")
  end

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
    if use_builtin_lsp_config then
      vim.lsp.config(server, opts)
      vim.lsp.enable(server)
    elseif lspconfig and lspconfig[server] then
      lspconfig[server].setup(opts)
    end
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

-- Local LLM via Ollama, optionally through OpenWebUI's Ollama proxy.
-- Examples:
--   NVIM_OLLAMA_URL=http://127.0.0.1:11434
--   NVIM_OLLAMA_URL=http://127.0.0.1:3000/ollama   (OpenWebUI)
--   NVIM_OLLAMA_MODEL=qwen2.5-coder:7b
local ollama = safe_require("ollama")
if ollama then
  local ollama_url = vim.env.NVIM_OLLAMA_URL or vim.env.OLLAMA_HOST or "http://127.0.0.1:11434"
  if not ollama_url:match("^https?://") then
    ollama_url = "http://" .. ollama_url
  end

  ollama.setup({
    model = vim.env.NVIM_OLLAMA_MODEL or "llama3.2",
    url = ollama_url,
    -- Upstream prompts Ask_About_Code / Explain_Code use $sel and can crash
    -- when no valid visual range exists. Override to buffer-safe prompts.
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

  vim.keymap.set("n", "<leader>oo", function()
    ollama_prompt_safe()
  end, { desc = "Ollama prompt" })
  vim.keymap.set("n", "<leader>og", function()
    ollama_prompt_safe("Generate_Code")
  end, { desc = "Ollama generate code" })
  vim.keymap.set("n", "<leader>or", function()
    ollama_prompt_safe("Raw")
  end, { desc = "Ollama raw prompt" })
  -- ollama.nvim expects <C-u> command mappings for visual selections.
  vim.keymap.set("x", "<leader>oo", ":<C-u>lua require('ollama').prompt()<CR>", { desc = "Ollama prompt (selection)" })
  vim.keymap.set(
    "x",
    "<leader>og",
    ":<C-u>lua require('ollama').prompt('Generate_Code')<CR>",
    { desc = "Ollama generate code (selection)" }
  )
  vim.keymap.set("x", "<leader>or", ":<C-u>lua require('ollama').prompt('Raw')<CR>", { desc = "Ollama raw prompt (selection)" })
  vim.keymap.set("n", "<leader>om", "<cmd>OllamaModel<CR>", { desc = "Ollama model" })
end

-- Codex AI helpers
local function detect_codex_cli()
  local candidates = {}
  local seen = {}

  local function add_candidate(path)
    if type(path) ~= "string" then
      return
    end
    local trimmed = vim.trim(path)
    if trimmed == "" or seen[trimmed] then
      return
    end
    seen[trimmed] = true
    table.insert(candidates, trimmed)
  end

  add_candidate(vim.env.CODEX_BIN)
  add_candidate(vim.fn.exepath("codex"))
  for _, path in ipairs(vim.fn.systemlist("which -a codex 2>/dev/null")) do
    add_candidate(path)
  end

  local legacy = nil
  for _, bin in ipairs(candidates) do
    vim.fn.system({ bin, "exec", "--help" })
    if vim.v.shell_error == 0 then
      return { bin = bin, mode = "exec" }
    end

    local help = vim.fn.system({ bin, "--help" })
    if vim.v.shell_error == 0 and help:find("%-%-plain") and legacy == nil then
      legacy = { bin = bin, mode = "plain" }
    end
  end

  return legacy
end

local codex_cli = detect_codex_cli()
if codex_cli then
  local function run_codex(prompt)
    if codex_cli.mode == "exec" then
      local output_file = vim.fn.tempname()
      local output = vim.fn.system({
        codex_cli.bin,
        "exec",
        "--color",
        "never",
        "--output-last-message",
        output_file,
        "--",
        prompt,
      })
      local shell_error = vim.v.shell_error
      local reply = ""

      if vim.fn.filereadable(output_file) == 1 then
        reply = table.concat(vim.fn.readfile(output_file), "\n")
        vim.fn.delete(output_file)
      end

      if shell_error ~= 0 then
        local err = vim.trim(reply ~= "" and reply or output)
        if err == "" then
          err = "Unknown error"
        end
        vim.notify("Codex error: " .. err, vim.log.levels.ERROR)
        return nil
      end

      if vim.trim(reply) == "" then
        reply = vim.trim(output)
      end
      return reply
    end

    local output = vim.fn.system({ codex_cli.bin, "--plain", prompt })
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
    if codex_cli.mode ~= "exec" then
      vim.notify("Interactive Codex terminal requires Codex CLI with `exec` support", vim.log.levels.WARN)
      return
    end
    vim.cmd("tabnew | terminal " .. vim.fn.fnameescape(codex_cli.bin))
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

-- OpenCode AI integration
local opencode = safe_require("opencode")
if opencode then
  vim.o.autoread = true
  vim.keymap.set({ "n", "x" }, "<leader>oa", function()
    opencode.ask("@this: ", { submit = true })
  end, { desc = "OpenCode ask + submit" })
  vim.keymap.set({ "n", "x" }, "<leader>os", function()
    opencode.select()
  end, { desc = "OpenCode select" })
  vim.keymap.set({ "n", "t" }, "<leader>ot", function()
    opencode.toggle()
  end, { desc = "OpenCode toggle" })
  vim.keymap.set({ "n", "x" }, "<leader>op", function()
    opencode.ask("@this: ", { submit = false })
  end, { desc = "OpenCode prompt (draft)" })
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
