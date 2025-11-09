# Neovim Cheat Sheet

This setup is driven by Home Manager and lazy.nvim. The `<leader>` key is `\` (backslash).

## Core Navigation & Search

| Mapping | Mode | Description |
| --- | --- | --- |
| `<leader>ff` | Normal | Telescope find files |
| `<leader>fg` | Normal | Telescope live grep (ripgrep) |
| `<leader>t`  | Normal | Toggle file tree (nvim-tree) |
| `<leader>e`  | Normal | Show diagnostics under cursor |
| `:NvimTreeToggle` | Command | Manually toggle the tree |

## AI & Assistant Tools

| Mapping / Command | Mode | Description |
| --- | --- | --- |
| `<leader>ca` | Normal | Prompt Codex AI for a free-form question |
| `<leader>ca` | Visual | Send the current selection to Codex for an explanation |
| `<leader>cT` | Normal | Open an interactive Codex terminal tab |
| `:Codex {prompt}` | Command | Ask Codex and view the reply in a floating window |
| `:CodexTerminal` | Command | Start the Codex CLI in a new tab |
| `<leader>cc` | Normal | Toggle Copilot Chat panel |
| `<leader>co` | Normal | Open ChatGPT floating window |
| `<leader>ci` | Visual | ChatGPT edit with instruction |

## Convenience

| Mapping / Command | Description |
| --- | --- |
| `:Mason` | Manage external LSP/DAP tools |
| `:Lazy`  | Lazy.nvim UI for plugins |
| `:Copilot` | Manually open Copilot panel |

## Useful Tips

- Codex reads `OPENAI_API_KEY`, sourcing `~/.config/secrets/openai.env` when present; keep that secret updated or export the key manually before launching Neovim.
- The Codex CLI supports `codex -m MODEL "prompt"` and will read from STDIN when no prompt is provided.
- Telescope shares the same `<leader>` prefix, so you can chain searches quickly.
- Treesitter-based highlighting & indentation are enabled by default.
- LSP servers for Lua, Bash, YAML, JSON, Go, TypeScript and Python are bootstrapped via mason.nvim.

Happy hacking!
