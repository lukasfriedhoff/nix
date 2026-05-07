# OpenCode Setup and Usage Guide

This document covers the OpenCode AI coding agent setup for this NixOS monorepo.

## Configuration

Configuration is stored in `~/.config/opencode/opencode.json`.

For personal Linux desktops, Home Manager enforces the Ollama backend on each activation via `modules/features/profile/desktop/home.nix`:

- model: `ollama/qwen3-coder:30b`
- provider base URL: `http://srv4.lab.h4xx.io:11434/v1` (localhost on `srv4`)
- global skills path: `~/.config/opencode/skills`

If `~/.config/opencode/skills` is empty, Home Manager bootstraps it once from:

- `/home/lukasf/git/lukasfriedhoff/nix/.opencode/skills`

### Current Setup

- **Model**: `ollama/qwen3-coder:30b` running on `srv4.lab.h4xx.io`
- **GPU**: AMD RX 7900 XT with ROCm acceleration

### Key Files

| File | Purpose |
|------|---------|
| `~/.config/opencode/opencode.json` | Main config (model, plugins, agents) |
| `~/.config/opencode/oh-my-opencode.json` | Oh-My-OpenCode agent mappings |
| `.opencode/skills/*/SKILL.md` | Project-specific skills |
| `.opencode/rules.md` | Project-specific rules |

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

The local `qwen3-coder:30b` model has limited context. Optimize with:

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
llm-srv4-start   # Start ollama and open-webui on srv4
```

### Stop LLM Server

```bash
llm-srv4-stop    # Stop services on srv4
```

### Check Status

```bash
llm-srv4-status  # Check service status
```

### GPU Monitoring

```bash
ssh srv4 "/opt/rocm-6.4.1/bin/rocm-smi"
```

## Neovim Integration

OpenCode is integrated with neovim via `opencode.nvim`.

### Keybindings

| Key | Mode | Action |
|-----|------|--------|
| `<leader>oa` | n/v | OpenCode ask (auto-submit) |
| `<leader>os` | n/v | OpenCode select menu |
| `<leader>ot` | n/t | Toggle OpenCode terminal |
| `<leader>op` | n/v | OpenCode prompt draft (no submit) |

### Context Placeholders

Use in prompts to inject context:

| Placeholder | Content |
|-------------|---------|
| `@this` | Current selection or cursor position |
| `@buffer` | Entire buffer content |
| `@diagnostics` | LSP errors in current file |
| `@diff` | Git diff output |
| `@visible` | Currently visible text |

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
