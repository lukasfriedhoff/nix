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

### llama.cpp (local/remote LLM)

| Mapping / Command | Mode | What it does |
| --- | --- | --- |
| `<leader>lo` | Normal/Visual | Prompt with current buffer/selection context |
| `<leader>lg` | Normal/Visual | Generate code prompt with context |
| `<leader>lr` | Normal/Visual | Raw prompt |
| `<leader>lm` | Normal | List configured llama.cpp models |

Environment variables used by Neovim:

- `NVIM_LLM_BASE_URL`
- `LLAMA_CPP_BASE_URL` (fallback)
- `NVIM_LLM_MODEL`

Current desktop profile wiring sets these in `modules/features/profile/desktop/home.nix`.

### OpenCode (opencode.nvim + srv4 llama.cpp)

| Mapping / Command | Mode | What it does |
| --- | --- | --- |
| `<leader>oa` | Normal/Visual | Ask OpenCode about `@this` immediately |
| `<leader>op` | Normal/Visual | Open an editable OpenCode prompt |
| `<leader>os` | Normal/Visual | Select an OpenCode prompt or command |
| `<leader>oc` | Normal/Terminal | Toggle the OpenCode pane |
| `<leader>ot` | Normal/Terminal | Toggle the OpenCode pane |
| `<leader>on` | Normal | Start a new OpenCode session |
| `<leader>ol` | Normal | Select an OpenCode session |
| `<leader>oi` | Normal | Interrupt the current OpenCode session |
| `<leader>ou` | Normal | Scroll OpenCode up half a page |
| `<leader>od` | Normal | Scroll OpenCode down half a page |
| `<leader>oo` | Normal/Visual | Send an operator range or selection to OpenCode |

The OpenCode pane auto-enters terminal input mode when opened or focused. Use
`<C-\><C-n>` to leave terminal input mode.

The OpenCode pane is a Neovim terminal buffer. If it ever shows `NORMAL` in the
statusline and does not accept input, press `i` in that pane to enter terminal
input mode. Use `<C-\><C-n>` when you intentionally want to leave terminal mode.

Home Manager now enforces OpenCode backend/model for personal desktops by patching:

- `~/.config/opencode/opencode.json`
- `model = llama-cpp/qwen3:8b`
- `provider.llama-cpp.options.baseURL = http://srv4.lab.h4xx.io:11434/v1` (or localhost on `srv4`)

## 8. Qwen via llama.cpp (Exact Workflow)

1. Start the llama.cpp runtime on `srv4`:

```bash
scripts/servers/setup-srv4-llm-runtime.sh
```

2. In your local shell before launching Neovim:

```bash
export NVIM_LLM_BASE_URL=http://srv4.lab.h4xx.io:11434/v1
export NVIM_LLM_MODEL=qwen3:8b
nvim
```

3. In Neovim:

- Press `\lm` and verify the model aliases appear.
- Use `\lo` or `\lg`.
- `\lo` asks about the current buffer context, or the visual selection when active.

## 9. llama.cpp Failure Notes

If a prompt fails:

- Verify `ssh srv4 'curl -fsS http://127.0.0.1:11434/health'`.
- Verify `env | grep -E 'NVIM_LLM_BASE_URL|NVIM_LLM_MODEL|LLAMA_CPP_BASE_URL'`.
- First use of a model alias may take a while because llama.cpp downloads the GGUF.

## 10. Session/Env Troubleshooting

If `env | grep NVIM_LLM_BASE_URL` is empty:

```bash
home-manager switch --flake /home/lukasf/git/lukasfriedhoff/nix#lukasf@desktop
exec $SHELL -l
```

Then verify:

```bash
env | grep -E 'NVIM_LLM_BASE_URL|NVIM_LLM_MODEL|LLAMA_CPP_BASE_URL|OPENWEBUI_URL'
```
