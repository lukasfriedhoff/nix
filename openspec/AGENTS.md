# OpenSpec Workflow for AI Agents

This document describes the spec-driven development workflow for AI coding assistants working on this repository.

## Overview

OpenSpec is a structured approach to making changes that:
1. Documents the intent and approach before coding
2. Tracks implementation progress
3. Archives completed work for reference

## Directory Structure

```
openspec/
├── project.md          # Project context (read first)
├── AGENTS.md           # This file - workflow instructions
├── specs/              # Current capability specifications
└── changes/            # Active change proposals
    ├── <change-name>/  # One directory per change
    │   ├── proposal.md # Problem, goals, approach
    │   ├── tasks.md    # Implementation checklist
    │   └── design.md   # Architecture decisions (optional)
    └── archive/        # Completed changes
```

## Workflow Commands

Use these Claude Code slash commands:

- `/openspec-proposal <name>` - Create a new change proposal
- `/openspec-apply` - Implement the current proposal
- `/openspec-archive` - Archive a completed change

## Creating a Change Proposal

### 1. Create the Proposal

Run `/openspec-proposal <change-name>` or manually create:

```
openspec/changes/<change-name>/
├── proposal.md
└── tasks.md
```

### 2. Write proposal.md

```markdown
# <Change Name>

## Problem Statement
What issue or limitation are we addressing?

## Goals
- Specific, measurable objectives
- What does success look like?

## Approach
High-level description of the solution.

## Files Affected
- `path/to/file1.nix` - Brief description of changes
- `path/to/file2.nix` - Brief description of changes

## Risks & Considerations
- Potential issues to watch for
- Breaking changes or migration needs
```

### 3. Write tasks.md

```markdown
# Implementation Tasks

## Phase 1: <Phase Name>
- [ ] Task 1
- [ ] Task 2

## Phase 2: <Phase Name>
- [ ] Task 3
- [ ] Task 4

## Verification
- [ ] Run `nix fmt`
- [ ] Run `nix flake check --no-build`
- [ ] Test on development machine
```

## Implementing Changes

### 1. Review the Proposal

Before implementing, ensure:
- The proposal is complete and approved
- You understand the goals and approach
- You've read the affected files

### 2. Follow tasks.md

Work through tasks sequentially:
- Mark tasks complete as you finish them
- Add new tasks if scope changes
- Note blockers or issues

### 3. Verify Changes

After implementation:
```bash
nix fmt
nix flake check --no-build
nix eval .#nixosConfigurations.tux-h4xx-01.config.system.build.toplevel --no-build
```

## Archiving Completed Changes

When a change is fully implemented and verified:

1. Move the change directory to archive:
   ```
   openspec/changes/<name>/ → openspec/changes/archive/<name>/
   ```

2. Add a completion note to proposal.md:
   ```markdown
   ## Completion
   - Completed: YYYY-MM-DD
   - Commit: <commit-hash>
   ```

## Best Practices

### Writing Good Proposals

- Be specific about the problem and solution
- List all files that will be modified
- Consider edge cases and migration needs
- Keep proposals focused (one logical change)

### During Implementation

- Commit frequently with clear messages
- Update tasks.md as you progress
- Ask for clarification before making assumptions
- Test changes incrementally

### Code Quality

- Follow existing patterns in the codebase
- Use `lib.mkDefault` for overridable values
- Use `lib.mkIf` for conditional configuration
- Keep modules focused and composable

## Example: Adding a New Feature

### 1. Create Proposal

```
openspec/changes/add-bluetooth-support/
├── proposal.md
└── tasks.md
```

### 2. proposal.md

```markdown
# Add Bluetooth Support

## Problem Statement
Desktop profiles lack Bluetooth configuration, requiring manual setup.

## Goals
- Enable Bluetooth on GNOME desktops
- Configure blueman for device management
- Add common Bluetooth packages

## Approach
Create a new feature module at `modules/features/hardware/bluetooth/`
that integrates with the desktop profile.

## Files Affected
- `modules/features/hardware/bluetooth/nixos.nix` - New module
- `modules/features/desktop/gnome/nixos.nix` - Enable Bluetooth

## Risks
- May conflict with existing audio configuration
- Power management considerations for laptops
```

### 3. tasks.md

```markdown
# Implementation Tasks

## Phase 1: Create Module
- [ ] Create `modules/features/hardware/bluetooth/nixos.nix`
- [ ] Add `hardwareProfiles.bluetooth.enable` option
- [ ] Configure bluez and blueman

## Phase 2: Integration
- [ ] Enable in GNOME desktop module
- [ ] Test with actual Bluetooth device

## Verification
- [ ] `nix fmt`
- [ ] `nix flake check --no-build`
- [ ] Test on tux-h4xx-01
```
