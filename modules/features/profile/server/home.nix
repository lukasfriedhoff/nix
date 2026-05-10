# Server profile for homelab and infrastructure servers
# Minimal CLI tools without GUI dependencies
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.profiles.server;
in
{
  options.profiles.server = {
    enable = lib.mkEnableOption "server home profile with minimal CLI tools";
  };

  config = lib.mkIf cfg.enable {
    # Server-specific packages (minimal, no GUI)
    home.packages = with pkgs; [
      htop
      ncdu
      tmux
      iotop
      lsof
      tcpdump
      strace
    ];

    # Server-focused shell aliases
    programs.bash.shellAliases = {
      # Service management
      sc = "sudo systemctl";
      jc = "journalctl";

      # Disk and storage
      df = "df -h";
      du = "du -sh";

      # Network diagnostics
      ports = "ss -tulanp";
      connections = "ss -s";
    };

    # Disable GUI-focused options
    programs.evolution.enable = lib.mkDefault false;
    programs.moonlight.enable = lib.mkDefault false;
  };
}
