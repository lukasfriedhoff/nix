# Neovim Cheat Sheet

This Neovim setup is managed via Home Manager.

- Leader key: `<leader>` = `\`
- Main config file: `modules/features/dev/neovim/nvim/init.lua`

## 1. Modes You Use Constantly

| Key | Mode | What it does |
| --- | --- | --- |
| `i` | Normal -> Insert | Insert before cursor |
| `a` | Normal -> Insert | Insert after cursor |
| `v` | Normal -> Visual | Character-wise selection |
| `V` | Normal -> Visual Line | Whole-line selection |
| `<C-v>` | Normal -> Visual Block | Column/block selection |
| `Esc` | Any -> Normal | Leave insert/visual/command prompts |
| `:` | Normal | Open command line |

## 2. Files, Search, Tree

| Mapping | Mode | What it does |
| --- | --- | --- |
| `<leader>ff` | Normal | Find files (Telescope) |
| `<leader>fg` | Normal | Live grep (Telescope + ripgrep) |
| `<leader>t` | Normal | Toggle file tree |
| `:NvimTreeToggle` | Command | Toggle file tree manually |

## 3. Windows / Panes (Split Management)

### Create splits

| Key | Mode | What it does |
| --- | --- | --- |
| `:split` | Normal | Horizontal split |
| `:vsplit` | Normal | Vertical split |
| `<C-w>s` | Normal | Horizontal split |
| `<C-w>v` | Normal | Vertical split |

### Move focus between panes

| Key | Mode | What it does |
| --- | --- | --- |
| `<C-w>h` | Normal | Focus left pane |
| `<C-w>j` | Normal | Focus lower pane |
| `<C-w>k` | Normal | Focus upper pane |
| `<C-w>l` | Normal | Focus right pane |
| `<C-w>w` | Normal | Next pane |
| `<C-w>p` | Normal | Previous pane |

### Resize panes

| Key | Mode | What it does |
| --- | --- | --- |
| `<C-w>+` | Normal | Increase height |
| `<C-w>-` | Normal | Decrease height |
| `<C-w>>` | Normal | Increase width |
| `<C-w><` | Normal | Decrease width |
| `<C-w>=` | Normal | Equalize all pane sizes |
| `<C-w>_` | Normal | Maximize current pane height |
| `<C-w>|` | Normal | Maximize current pane width |

### Re-arrange panes

| Key | Mode | What it does |
| --- | --- | --- |
| `<C-w>H` | Normal | Move current pane to far left |
| `<C-w>J` | Normal | Move current pane to bottom |
| `<C-w>K` | Normal | Move current pane to top |
| `<C-w>L` | Normal | Move current pane to far right |
| `<C-w>T` | Normal | Pop current pane out into a new tab |

### Close panes

| Key | Mode | What it does |
| --- | --- | --- |
| `<C-w>q` | Normal | Close current pane |
| `:q` | Normal | Quit current window |
| `:only` | Normal | Keep only current pane, close others |

## 4. Tabs

| Key | Mode | What it does |
| --- | --- | --- |
| `:tabnew` | Normal | New tab |
| `gt` | Normal | Next tab |
| `gT` | Normal | Previous tab |
| `:tabn` | Normal | Next tab |
| `:tabp` | Normal | Previous tab |
| `:tabclose` | Normal | Close current tab |
| `:tabs` | Normal | List tabs |
| `:tabmove N` | Normal | Move current tab to index `N` |

## 5. Buffers

| Key | Mode | What it does |
| --- | --- | --- |
| `:ls` | Normal | List open buffers |
| `:bnext` / `:bn` | Normal | Next buffer |
| `:bprev` / `:bp` | Normal | Previous buffer |
| `:buffer N` | Normal | Switch to buffer `N` |
| `:bd` | Normal | Delete (close) current buffer |
| `:e <path>` | Normal | Edit/open file path |

## 6. Diagnostics / LSP

| Mapping | Mode | What it does |
| --- | --- | --- |
| `<leader>e` | Normal | Show diagnostics under cursor |
| `:Mason` | Command | Manage LSP/tooling installations |
| `:Lazy` | Command | Plugin manager UI |

LSP servers are auto-installed for Lua, Bash, YAML, JSON, Go, TypeScript, and Python in this setup.

## 7. AI Tooling (Configured Here)

### Codex

| Mapping / Command | Mode | What it does |
| --- | --- | --- |
| `<leader>ca` | Normal | Ask Codex free-form question |
| `<leader>ca` | Visual | Ask Codex about selected code |
| `<leader>cT` | Normal | Open Codex terminal tab |
| `:Codex {prompt}` | Command | Ask Codex in floating window |
| `:CodexTerminal` | Command | Start Codex CLI in tab |

### Copilot / Chat

| Mapping / Command | Mode | What it does |
| --- | --- | --- |
| `<leader>cc` | Normal | Toggle Copilot Chat |
| `:Copilot` | Command | Copilot command panel |

### Ollama (local/remote LLM)

| Mapping / Command | Mode | What it does |
| --- | --- | --- |
| `<leader>oo` | Normal/Visual | Ollama prompt picker |
| `<leader>og` | Normal/Visual | Generate code prompt |
| `<leader>or` | Normal/Visual | Raw prompt |
| `<leader>om` | Normal | Choose model |

Environment variables used by Neovim:

- `NVIM_OLLAMA_URL` (preferred)
- `OLLAMA_HOST` (fallback)
- `NVIM_OLLAMA_MODEL`

Current desktop profile wiring sets these in `modules/features/profile/desktop/home.nix`.

### OpenCode (opencode.nvim + srv4 Ollama)

| Mapping / Command | Mode | What it does |
| --- | --- | --- |
| `<leader>oa` | Normal/Visual | OpenCode ask (`@this`) + submit |
| `<leader>op` | Normal/Visual | OpenCode ask draft (`@this`) without submit |
| `<leader>os` | Normal/Visual | OpenCode action picker |
| `<leader>ot` | Normal/Terminal | Toggle OpenCode pane |

Home Manager now enforces OpenCode backend/model for personal desktops by patching:

- `~/.config/opencode/opencode.json`
- `model = ollama/qwen3-coder:30b`
- `provider.ollama.options.baseURL = http://srv4.lab.h4xx.io:11434/v1` (or localhost on `srv4`)

## 8. Qwen via Ollama (Exact Workflow)

1. Pull a Qwen model on the Ollama host:

```bash
ssh srv4 'ollama pull qwen3-coder:30b'
```

2. In your local shell before launching Neovim:

```bash
export NVIM_OLLAMA_URL=http://srv4.lab.h4xx.io:11434
export NVIM_OLLAMA_MODEL=qwen3-coder:30b
nvim
```

3. In Neovim:

- Press `\om` and verify the model appears.
- Use `\oo` or `\og`.
- `\oo` asks about the current buffer context (not just selection).

## 9. Ollama Failure Notes (`start_col must be <= end_col`)

If you hit:

`Error executing lua ... start_col must be less than or equal to end_col`

then use these rules:

- For selected text prompts, select in visual mode and use `\oo` / `\og` / `\or`.
- If a prompt fails, press `Esc` first and retry in normal mode.
- Ensure you are on the latest repo config where:
  - visual mappings use the plugin-recommended `<C-u>` command form
  - `Ask_About_Code` / `Explain_Code` prompts are overridden to use `$buf` instead of `$sel`

## 10. Session/Env Troubleshooting

If `env | grep NVIM_OLLAMA_URL` is empty:

```bash
home-manager switch --flake /home/lukasf/git/lukasfriedhoff/nix#lukasf@desktop
exec $SHELL -l
```

Then verify:

```bash
env | grep -E 'NVIM_OLLAMA_URL|NVIM_OLLAMA_MODEL|OLLAMA_HOST|OPENWEBUI_URL'
```
