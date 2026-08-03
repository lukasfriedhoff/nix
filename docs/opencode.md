# OpenCode Setup and Usage Guide

This document covers the OpenCode AI coding agent setup for this NixOS monorepo.

## Configuration

Configuration is stored in `~/.config/opencode/opencode.json`.
Project-specific defaults live in `opencode.jsonc` at the repository root.

For personal Linux desktops, Home Manager enforces the llama.cpp backend on each activation via `modules/features/profile/desktop/home.nix`:

- model: `llama-cpp/qwen3:8b`
- provider base URL: `http://srv4.lab.h4xx.io:11434/v1` (localhost on `srv4`)
- global skills path: `~/.config/opencode/skills`

If `~/.config/opencode/skills` is empty, Home Manager bootstraps it once from:

- `/home/lukasf/git/lukasfriedhoff/nix/.opencode/skills`

### Current Setup

- **Model**: `llama-cpp/qwen3:8b` running on `srv4.lab.h4xx.io`
- **Runtime**: llama.cpp on `srv4`; Vulkan/ROCm images can be selected with `LLAMA_CPP_IMAGE`
- **Kimi K3**: `kimi-api/kimi-k3` via Moonshot/Kimi API when `MOONSHOT_API_KEY` is set
- **AirLLM**: `airllm-srv4/kimi-k3` uses an SSH-forwarded experimental srv4 endpoint on local port `11435`

### Key Files

| File | Purpose |
|------|---------|
| `~/.config/opencode/opencode.json` | Main config (model, plugins, agents) |
| `~/.config/opencode/oh-my-opencode.json` | Oh-My-OpenCode agent mappings |
| `opencode.jsonc` | Repo instructions, compaction, watcher ignores, safety permissions |
| `.opencode/agents/review.md` | Read-only repo review subagent |
| `.opencode/skills/*/SKILL.md` | Project-specific skills |
| `.opencode/rules.md` | Project-specific rules |

### Project Defaults

The checked-in `opencode.jsonc` follows current OpenCode config patterns:

- loads `AGENTS.md` and key repo docs through `instructions`
- enables automatic compaction with tool-output pruning
- ignores noisy local paths such as `.git`, `.direnv`, build results, and `.opencode/node_modules`
- asks before local commits, pushes, and NixOS switches; denies broad `rm -rf *`

## Installed Plugins

| Plugin | Purpose |
|--------|---------|
| `oh-my-opencode` | Background agents, LSP/AST tools, MCP integration |
| `@op1/workspace` | Plans, notepads, worktrees, tmux, safety hooks |
| `opencode-agent-skills` | Dynamic skills discovery |
| `opencode-dynamic-context-pruning` | Token optimization via context pruning |
| `opencode-snip` | 60-90% token reduction for shell output |
| `opencode-direnv` | Auto-load .envrc environment variables |
| `claude-code-safety-net` | Catches destructive commands |
| `envsitter-guard` | Prevents .env file leaks |
| `opencode-agent-tmux` | Tmux pane integration |
| `opencode-notify` | Native OS notifications |
| `opencode-handoff` | Session handoff prompts |
| `opencode-quota` | Token usage tracking |

## Agents

### Primary Agents

| Agent | Purpose | Use When |
|-------|---------|----------|
| `build` | Full capabilities, can edit files | Implementing features, fixing bugs |
| `plan` | Read-only, analysis and planning | Designing architecture, reviewing code |

### Oh-My-OpenCode Agents

| Agent | Purpose |
|-------|---------|
| `sisyphus` | Main orchestrator, delegates to specialists |
| `oracle` | Architecture and debugging expert |
| `librarian` | Code search and documentation |
| `explore` | Fast codebase exploration |
| `prometheus` | Performance optimization |
| `metis` | Strategic planning |
| `atlas` | Large-scale refactoring |

Switch agents with `tab` key in the TUI.

## Skills

Skills are reusable instructions loaded by agents. Located in `.opencode/skills/`.

### Available Skills

| Category | Skills |
|----------|--------|
| Nix | `nix`, `flake`, `home-manager`, `sops-secrets` |
| System | `systemd`, `podman`, `ssh`, `wireguard`, `neovim-config` |
| Kubernetes | `kubernetes`, `flux`, `helm`, `kustomize`, `cilium`, `cert-manager` |
| Git | `git-master` |

### Creating Skills

```markdown
---
name: my-skill
description: What this skill does
globs:
  - "**/*.ext"
---

# Skill Name

Instructions and patterns for the AI...
```

## Commands

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `Enter` | Send message |
| `Ctrl+C` | Cancel/Interrupt |
| `Tab` | Switch agent |
| `Ctrl+P` | Command palette |
| `Esc` | Exit/Back |

### Slash Commands

| Command | Description |
|---------|-------------|
| `/help` | Show available commands |
| `/clear` | Clear conversation |
| `/compact` | Compress conversation context |
| `/status` | Show session status |
| `/model` | Change model |
| `/handoff` | Create handoff for new session |

### @op1/workspace Commands

| Command | Description |
|---------|-------------|
| `/plan` | Create/view execution plan |
| `/notepad` | Open scratchpad for notes |
| `/worktree` | Manage git worktrees |

## Use Cases

### 1. Implementing a New NixOS Module

```
Create a NixOS module for <service> with:
- Enable option
- Configuration options for <settings>
- Systemd service
- Firewall rules
```

The agent will:
1. Load `nix`, `flake`, `systemd` skills
2. Create module in `modules/features/<name>/nixos.nix`
3. Add options with `lib.mkOption`
4. Configure systemd service

### 2. Adding a Kubernetes Deployment

```
Deploy <app> to the cluster using Flux with:
- HelmRelease
- ConfigMap for settings
- Ingress with TLS
```

The agent will:
1. Load `kubernetes`, `flux`, `helm`, `cert-manager` skills
2. Create HelmRelease in appropriate directory
3. Configure ingress with cert-manager annotations

### 3. Debugging a Service

```
The <service> isn't starting. Check logs and fix it.
```

The agent will:
1. Check `systemctl status`
2. Read `journalctl` logs
3. Identify the issue
4. Propose and apply fix

### 4. Code Review

Switch to `plan` agent, then:

```
Review the changes in this branch for:
- Security issues
- Performance concerns
- Best practices
```

### 5. Refactoring

```
Refactor the <module> to:
- Split into smaller files
- Add proper error handling
- Follow existing patterns
```

### 6. Creating Plans (@op1/workspace)

```
/plan Create an execution plan for implementing <feature>
```

The agent will:
1. Analyze requirements
2. Break into tasks
3. Save plan to `.opencode/plans/`
4. Track progress as you work

### 7. Multi-Branch Work (worktrees)

```
Create a worktree for feature/my-feature and start working
```

The agent will:
1. Create git worktree
2. Open new tmux window
3. Start opencode session in worktree

### 8. Session Handoff

When context is getting long:

```
/handoff
```

Creates a focused prompt summarizing:
- What was accomplished
- Current state
- Next steps

Start new session with the handoff prompt.

## Context Optimization

### Token Limits

The local llama.cpp models have limited context compared to hosted frontier models. Optimize with:

1. **opencode-snip**: Automatically reduces shell output
2. **opencode-dynamic-context-pruning**: Prunes stale tool outputs
3. **/compact**: Manually compress conversation
4. **/handoff**: Start fresh session with summary

### Best Practices

- Start with clear, specific prompts
- Use `/compact` when context grows large
- Use `plan` agent for analysis (doesn't need edit context)
- Use `/handoff` for long-running tasks
- Break large tasks into smaller sessions

## Server Management

### Start LLM Server

```bash
llm-srv4-start   # Start llama.cpp and Open WebUI on srv4
```

### Stop LLM Server

```bash
llm-srv4-stop    # Stop services on srv4
```

### Check Status

```bash
llm-srv4-status  # Check service status
```

### List srv4 Models

```bash
llm-srv4-models
```

### Use Kimi K3

Kimi K3 is wired as a hosted OpenAI-compatible provider because local weights are
not generally available yet. Do not put the API key in Git or Nix store paths.
Authenticate with OpenCode or export it in a shell:

```bash
export MOONSHOT_API_KEY=...
opencode-kimi-api
```

### Use qwen3-coder 30B

The 30B coder model is available but not the default because the CPU image can
saturate srv4 while loading it. Use it only when the ROCm/Vulkan runtime is
healthy:

```bash
opencode-qwen3-coder
```

### Use AirLLM Experiment

AirLLM is exposed as `airllm-srv4/*` so OpenCode can use it once an
OpenAI-compatible AirLLM service is running on srv4. The service binds to
loopback and must be reached through SSH:

```bash
AIRLLM_MODEL_ID=owner/model scripts/servers/setup-srv4-airllm-runtime.sh
airllm-srv4-tunnel
```

Keep the tunnel running in a separate terminal, then start OpenCode:

```bash
opencode-airllm
```

### GPU Monitoring

```bash
ssh srv4 "/opt/rocm-6.4.1/bin/rocm-smi"
```

## Neovim Integration

OpenCode is integrated with Neovim through `opencode.nvim`. Neovim starts
`opencode --port` in a right-side pane and talks to the OpenCode server through
the plugin API. Avoid routing this through CodeCompanion ACP; that creates a
separate CodeCompanion chat buffer and has been fragile in split-heavy layouts.

### Keybindings

| Key | Mode | Action |
|-----|------|--------|
| `<leader>oa` | n/v | Ask OpenCode about `@this` immediately |
| `<leader>op` | n/v | Open an editable OpenCode prompt |
| `<leader>os` | n/v | Select an OpenCode prompt or command |
| `<leader>oc` | n/t | Toggle the OpenCode pane |
| `<leader>ot` | n/t | Toggle the OpenCode pane |
| `<leader>on` | n | Start a new OpenCode session |
| `<leader>ol` | n | Select an OpenCode session |
| `<leader>oi` | n | Interrupt the current OpenCode session |
| `<leader>ou` | n | Scroll OpenCode up half a page |
| `<leader>od` | n | Scroll OpenCode down half a page |
| `<leader>oo` | n/v | Send an operator range or selection to OpenCode |

The OpenCode pane auto-enters terminal input mode when opened or focused. Use
`<C-\><C-n>` to leave terminal input mode and use Neovim window commands.

### Context Placeholders

Use `opencode.nvim` context tokens in prompts:

| Token | Content |
|-------------|---------|
| `@this` | Current operator range or visual selection, else cursor position |
| `@buffer` | Current buffer |
| `@buffers` | Open buffers |
| `@visible` | Visible buffer text |
| `@diagnostics` | Current buffer diagnostics |
| `@quickfix` | Quickfix list |
| `@diff` | Current git diff |

## Troubleshooting

### Plugin Loading Errors

If plugins fail to load with native dependency errors:

1. Ensure `nix-ld` is configured in NixOS
2. Run `sudo nixos-rebuild switch`
3. Clear cache: `rm -rf ~/.cache/opencode/node_modules`
4. Restart opencode

### Model Not Found

Check the model is available:

```bash
curl http://srv4.lab.h4xx.io:11434/api/tags
```

### Slow Responses

1. Check GPU utilization: `ssh srv4 rocm-smi`
2. Ensure model is loaded: `curl http://srv4.lab.h4xx.io:11434/api/ps`
3. Consider smaller model for faster responses

### Skills Not Loading

1. Check skill files have correct YAML frontmatter
2. Verify skill directory structure: `.opencode/skills/<name>/SKILL.md`
3. Restart opencode to reload skills

## Adding New Skills

1. Create directory: `.opencode/skills/<skill-name>/`
2. Create `SKILL.md` with frontmatter:

```markdown
---
name: skill-name
description: What this skill covers
globs:
  - "pattern/**/*.ext"
---

# Skill Title

## Overview
What this skill helps with...

## Key Patterns
Code examples and patterns...

## Commands
Relevant commands...

## Best Practices
Guidelines...
```

3. Add to agent skills in `opencode.json`:

```json
"agent": {
  "build": {
    "skills": ["...", "skill-name"]
  }
}
```

4. Restart opencode

## Resources

- [OpenCode Docs](https://opencode.ai/docs/)
- [Plugins](https://opencode.ai/docs/plugins/)
- [Skills](https://opencode.ai/docs/skills/)
- [awesome-opencode](https://github.com/awesome-opencode/awesome-opencode)
