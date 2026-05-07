---
name: neovim-config
description: Neovim configuration with Lua and Nix
globs:
  - "**/neovim/**"
  - "**/nvim/**"
  - "**/*.lua"
---

# Neovim Configuration Skill

Neovim setup with Nix and Lua configuration.

## Nix Plugin Management

```nix
programs.neovim = {
  enable = true;
  plugins = with pkgs.vimPlugins; [
    nvim-treesitter
    telescope-nvim
    nvim-lspconfig
  ];
  extraLuaConfig = builtins.readFile ./init.lua;
  extraPackages = with pkgs; [ ripgrep fd ];
};
```

## Lua Patterns

```lua
-- Safe require
local ok, mod = pcall(require, "module")
if not ok then return end

-- Keymaps
vim.keymap.set("n", "<leader>ff", function()
  require("telescope.builtin").find_files()
end, { desc = "Find files" })

-- Options
vim.o.number = true
vim.opt.clipboard = "unnamedplus"
```

## LSP Setup

```lua
local lspconfig = require("lspconfig")
lspconfig.lua_ls.setup({
  settings = {
    Lua = { diagnostics = { globals = { "vim" } } }
  }
})
```

## Plugin Configuration

```lua
require("plugin").setup({
  option = value,
})
```

## Best Practices

- Use `pcall` for optional plugin loading
- Keep keymaps descriptive with `desc`
- Separate config into logical sections
