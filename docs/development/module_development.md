# Module Development Guide

This guide explains how to create and maintain feature modules in this Nix repository following the established patterns and conventions.

## Module Structure

Feature modules are organized under `modules/features/<feature>/` with the following possible files:

- `nixos.nix` - NixOS configuration
- `home.nix` - Home Manager configuration  
- `darwin.nix` - nix-darwin configuration
- `default.nix` - Optional module entry point

## Basic Module Template

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.lukasf.<feature>;
in
{
  options.lukasf.<feature> = {
    enable = lib.mkEnableOption "Enable <feature>";
    
    # Add other options here
    package = lib.mkPackageOption pkgs "<package name>" { };
  };

  config = lib.mkIf cfg.enable {
    # Module configuration here
  };
}
```

## Option Patterns

### Enable Flag
All feature modules should provide an `enable` option using `lib.mkEnableOption`:

```nix
options.lukasf.<feature>.enable = lib.mkEnableOption "Enable <feature>";
```

### Package Wrapping
When a module wraps a primary package, use `lib.mkPackageOption`:

```nix
options.lukasf.<feature>.package = lib.mkPackageOption pkgs "package-name" { };
```

### Network Options
For modules that bind to network ports, provide `openFirewall`:

```nix
options.lukasf.<feature>.openFirewall = lib.mkOption {
  type = lib.types.bool;
  default = false;
  description = "Open firewall ports for <feature>";
};
```

### Path and Secret Options
For options that reference files or secrets, use appropriate types:

```nix
options.lukasf.<feature>.configFile = lib.mkOption {
  type = lib.types.nullOr lib.types.path;
  default = null;
  description = "Path to configuration file";
};
```

## Configuration Patterns

### Guarding with lib.mkIf
Always guard module configuration with `lib.mkIf cfg.enable`:

```nix
config = lib.mkIf cfg.enable {
  # Configuration that only applies when enabled
  services.<feature> = {
    enable = true;
    # ... other settings
  };
};
```

### Default Values with lib.mkDefault
Use `lib.mkDefault` for values that should be easily overridden:

```nix
services.<feature>.port = lib.mkDefault 8080;
```

### Combining Configurations with lib.mkMerge
When combining conditional and unconditional defaults:

```nix
config = lib.mkIf cfg.enable (lib.mkMerge [
  {
    # Unconditional settings
    services.<feature>.enable = true;
  }
  (lib.mkIf cfg.someCondition {
    # Conditional settings
    services.<feature>.option = cfg.value;
  })
]);
```

## Module Integration Patterns

### Accessing Other Module Options
Modules can reference options from other modules:

```nix
config = lib.mkIf cfg.enable {
  # Access other module options
  environment.systemPackages = lib.mkIf cfg.installTools [ pkgs.<tool> ];
};
```

### Using lib.getExe for Executables
When referencing executables from packages:

```nix
systemd.services.<service> = {
  executable = "${cfg.package}/bin/<executable>";
  # OR
  executable = lib.getExe cfg.package;
};
```

## File Structure Guidelines

### Feature Organization
Organize code by concern rather than by system type:

```
modules/
└── features/
    └── <feature>/
        ├── nixos.nix
        ├── home.nix
        └── darwin.nix
```

### Subdirectory Organization
For complex features with multiple components:

```
modules/
└── features/
    └── <feature>/
        ├── nixos.nix
        ├── home.nix
        ├── darwin.nix
        ├── networking/
        │   ├── nixos.nix
        │   └── home.nix
        └── database/
            ├── nixos.nix
            └── home.nix
```

## Best Practices

### Sensible Defaults
Provide defaults that work across different host profiles:

```nix
options.lukasf.<feature>.port = lib.mkOption {
  type = lib.types.port;
  default = 8080;
  description = "Port to listen on";
};
```

### Clear Documentation
Document all options clearly:

```nix
options.lukasf.<feature>.configFile = lib.mkOption {
  type = lib.types.nullOr lib.types.path;
  default = null;
  description = ''
    Path to the configuration file.
    
    If null, a default configuration will be generated.
  '';
};
```

### Dependency Management
Use `lib.mkIf` to conditionally include dependencies:

```nix
environment.systemPackages = lib.mkIf cfg.enable [ cfg.package ];
```

### Service Integration
For services that should be available on all systems:

```nix
config = lib.mkIf cfg.enable {
  # Services available on all systems
  environment.systemPackages = [ cfg.package ];
  
  # System-specific configurations
  systemd.services.<service> = {
    # Service configuration
  };
};
```

## Host Configuration Examples

### Enabling Features
```nix
# Enable a feature module
lukasf.<feature>.enable = true;

# Enable with specific settings
lukasf.<feature> = {
  enable = true;
  package = pkgs.<different-package>;
};
```

### Overriding Defaults
```nix
# Override defaults in host configuration
lukasf.<feature>.port = 9000;
```

### Conditional Configuration
```nix
# Enable only on specific hosts
lib.mkIf (config.networking.hostName == "my-host") {
  lukasf.<feature>.enable = true;
};
```

## Testing Modules

### Validation
All modules should validate that required options are properly configured:

```nix
config = lib.mkIf cfg.enable {
  assertions = [
    {
      assertion = cfg.someValue != null;
      message = "Some value must be configured for the <feature> module";
    }
  ];
  
  # Configuration
};
```

### Integration Testing
Test modules in combination with other modules to ensure they integrate properly:

```nix
# Test with other modules
lukasf.<feature>.enable = true;
lukasf.<other-feature>.enable = true;
```

## Examples

### Simple Feature Module
```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.lukasf.<feature>;
in
{
  options.lukasf.<feature> = {
    enable = lib.mkEnableOption "Enable <feature>";

    package = lib.mkPackageOption pkgs "<package-name>" { };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port to listen on";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    systemd.services.<service> = {
      enable = true;
      description = "<feature> service";
      executable = lib.getExe cfg.package;
      # ... service configuration
    };
  };
}
```

### Feature with Dependencies
```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.lukasf.<feature>;
in
{
  options.lukasf.<feature> = {
    enable = lib.mkEnableOption "Enable <feature>";
    
    package = lib.mkPackageOption pkgs "<package-name>" { };
    
    database = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Database configuration";
    };
    
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open firewall ports";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.database != null || config.lukasf.database.enable;
        message = "Either database option must be set or database module must be enabled";
      }
    ];

    environment.systemPackages = [ cfg.package ];

    # Enable firewall if needed
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ cfg.port ];

    # Service configuration
    systemd.services.<service> = {
      description = "<feature> service";
      executable = lib.getExe cfg.package;
      # ... other service settings
    };
  };
}
```