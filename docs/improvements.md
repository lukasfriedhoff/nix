# Nix Monorepo: Code Review, Restructuring & New Modules

## Code Review Findings

### Structural Issues Identified & Fixed
1. **Inconsistent host grouping** - Personal desktops and `macbook-pro` sat at `hosts/` root while homelab and dacoso servers were grouped in subdirs. **Fixed**: Grouped into `hosts/personal/`, `hosts/homelab/`, `hosts/work/`.
2. **`hosts/darwin/` was a module, not a host** - Contained macOS platform base config but lived alongside actual hosts. **Fixed**: Moved to `modules/darwin/`.
3. **No `modules/darwin/`** - macOS system modules had no proper home. **Fixed**: Created `modules/darwin/` with `default.nix` and `settings.nix`.
4. **`home/programs/` mixed categories with standalone programs** - `chromium/`, `evolution/`, `stylix/` were standalone alongside category dirs. **Fixed**: Moved into `utils/` and new `theming/` category.
5. **`disk-config.nix` vs `disko.nix`** - Inconsistent naming. **Fixed**: Standardized to `disko.nix` everywhere.
6. **`_template` used underscore** - Everything else was kebab-case. **Fixed**: Renamed to `template`.
7. **`lib/default.nix` never used** - Defined helpers but nothing imported them. **Fixed**: Wired `myLib` into `flake.nix`.
8. **Repetitive module lists in `flake.nix`** - 6 lists shared 7 common entries via copy-paste. **Fixed**: Refactored into composable `coreModules`, `desktopExtras`, `serverExtras` layers.
9. **Hardcoded `users.users.lukasf`** in `gnome.nix`. **Fixed**: Parameterized with `linuxUser` specialArg.
10. **Hardcoded `nvidiaBusId`** in `gaming.nix`. **Fixed**: Added as a module option with default `"PCI:1:0:0"`.

---

## Directory Structure (Post-Restructure)

```
hosts/
├── personal/
│   ├── tux-h4xx-01/            # GNOME desktop (Tuxedo InfinityBook)
│   ├── tab-h4xx-02/            # GNOME desktop (ASUS Vivobook)
│   └── srv4-vm-01/             # Plasma desktop (VM)
├── homelab/
│   ├── srv1/                   # Kubernetes + Ceph node
│   ├── srv2/                   # Kubernetes + Ceph node
│   └── template/               # Template for new hosts
└── work/
    ├── macbook-pro/            # macOS (nix-darwin)
    ├── docker-host-01/         # Docker hosting (dacoso)
    └── timebutler-test-vm/     # Test VM (dacoso)

modules/
├── nixos/
│   ├── hardware/               # Tuxedo, ASUS, SuperMicro
│   ├── profiles/               # base, desktop/{gnome,plasma,gaming,laptop,libreoffice}, homelab/*, dacoso/*, server/*
│   └── services/               # ceph, wireguard, nix-cache, remote-builders, seaweedfs, kvm, icarus
└── darwin/
    ├── default.nix             # macOS base: nix config, user, system path
    └── settings.nix            # macOS defaults: Finder, login, locale

home/
├── default.nix                 # Main entry point, conditional enables
├── hosts/tux.nix               # tux-specific HM overrides
├── platforms/
│   ├── linux/default.nix       # Linux packages, systemd SSH agent
│   └── macos/default.nix       # macOS packages, aliases, AeroSpace + SketchyBar
├── shell/bash/                 # Bash config + alias completions
└── programs/
    ├── dev/                    # git, neovim, vscode, lazygit, codex, claude, oh-my-opencode
    ├── devops/                 # kubectl, k9s, velero, s3, sops-age
    ├── utils/                  # alacritty, starship, gpg, ssh, chromium, evolution
    ├── work/                   # cassandra-tools, mariadb-tools, maven-config
    ├── gaming/                 # icarus-mod-manager, moonlight
    ├── desktop/                # aerospace, sketchybar
    ├── theming/                # stylix (Catppuccin Mocha)
    └── archive/                # cyberduck (not imported)
```

---

## New Modules

### Moonlight Client (`home/programs/gaming/moonlight/`)
- Game streaming client for NVIDIA GameStream / Sunshine
- Enabled on all personal Linux desktops (tux, tab, srv4)
- Options: `programs.moonlight.enable`, `programs.moonlight.package`
- Creates XDG desktop entry on Linux

### AeroSpace (`home/programs/desktop/aerospace/`)
- i3-like tiling window manager for macOS
- Installed via homebrew cask, config managed by home-manager
- Default config: vim-style focus/move (alt+hjkl), workspaces (alt+1-9), gaps, service mode for reload/tree ops
- Config written to `~/.config/aerospace/aerospace.toml` (TOML format)
- Options: `programs.aerospace.enable`, `programs.aerospace.settings`

### SketchyBar (`home/programs/desktop/sketchybar/`)
- Custom macOS status bar
- Installed via homebrew tap (`FelixKratz/formulae`)
- Default config: Catppuccin Mocha theme, AeroSpace workspace indicators, front app, clock, battery, CPU
- Config written to `~/.config/sketchybar/sketchybarrc` (executable shell script)
- Activation hook reloads SketchyBar after home-manager switch
- Options: `programs.sketchybar.enable`, `programs.sketchybar.extraConfig`

---

## flake.nix Module Composition

Module lists are now composed from reusable layers:

```
coreModules (all NixOS hosts)
├── base.nix, wireguard, nix-cache, remote-builders, seaweedfs, ceph, sops

desktopExtras (desktop hosts only)
├── libreoffice, stylix, home-manager

serverExtras (server hosts only)
├── kvm, comin

Composed:
  baseDesktopModules     = coreModules ++ desktopExtras
  gnomeDesktopModules    = baseDesktopModules ++ [gnome, laptop]
  plasmaDesktopModules   = baseDesktopModules ++ [plasma]
  baseServerModules      = coreModules ++ serverExtras ++ [dacoso/server]
  homelabServerModules   = coreModules ++ serverExtras ++ [kubernetes, gitops]
  personalHomelabModules = coreModules ++ serverExtras ++ [personal-server, kubernetes]
```

---

## Verification

```bash
# Format check
nix fmt --check .

# Flake evaluation
nix flake check

# Dry-run builds
nix build .#nixosConfigurations.tux-h4xx-01.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.srv4-vm-01.config.system.build.toplevel --dry-run
nix build .#nixosConfigurations.docker-host-01.config.system.build.toplevel --dry-run
nix build .#homeConfigurations."lukasf@desktop".activationPackage --dry-run

# Full rebuild (on target host)
sudo nixos-rebuild switch --flake .#tux-h4xx-01
darwin-rebuild switch --flake .#macbook-pro
```
