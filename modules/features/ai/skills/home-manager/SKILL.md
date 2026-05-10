---
name: home-manager
description: Home-manager module patterns and configuration
globs:
  - "**/home.nix"
  - "**/home-manager/**"
---

# Home-Manager Skill

User environment management with home-manager.

## Module Structure

```nix
{ config, lib, pkgs, ... }:
{
  options.my.feature = {
    enable = lib.mkEnableOption "feature description";
  };

  config = lib.mkIf config.my.feature.enable {
    # Configuration here
  };
}
```

## Common Patterns

```nix
# Session variables
home.sessionVariables = {
  EDITOR = "nvim";
};

# Packages
home.packages = with pkgs; [ ripgrep fd ];

# Dotfiles
home.file.".config/app/config".text = ''
  configuration here
'';

# XDG directories
xdg.configFile."app/config".source = ./config;
```

## Programs Module

```nix
programs.git = {
  enable = true;
  userName = "name";
  userEmail = "email";
};
```

## Activation Scripts

```nix
home.activation.myScript = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  # Script runs on activation
'';
```

## State Version

Always set `home.stateVersion` and don't change it after initial setup.
