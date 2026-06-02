{
  config,
  lib,
  ...
}:

let
  cfg = config.lukasf.hydraBuilder;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.lukasf.hydraBuilder = {
    enable = mkEnableOption "Hydra CI builder for this flake";

    hydraURL = mkOption {
      type = types.str;
      default = "https://hydra.h4xx.io";
      description = "Public Hydra URL.";
    };

    listenHost = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "Hydra web listener address.";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Hydra web port.";
    };

    notificationSender = mkOption {
      type = types.str;
      default = "hydra@h4xx.io";
      description = "Hydra notification sender.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the Hydra web port in the firewall.";
    };

    minimumDiskFree = mkOption {
      type = types.int;
      default = 20;
      description = "Minimum free disk space in GiB for Hydra queue runner.";
    };

    maxServers = mkOption {
      type = types.int;
      default = 8;
      description = "Maximum Hydra web worker count.";
    };
  };

  config = mkIf cfg.enable {
    services.hydra = {
      enable = true;
      inherit (cfg)
        hydraURL
        listenHost
        port
        notificationSender
        minimumDiskFree
        maxServers
        ;
      useSubstitutes = true;
      extraConfig = ''
        evaluator_max_memory_size = 4096
        max_output_size = 4294967296
      '';
    };

    nix.settings = {
      allowed-uris = [
        "github:"
        "git+https://github.com/"
        "https://github.com/"
      ];
      trusted-users = lib.mkAfter [
        "hydra"
        "hydra-queue-runner"
      ];
    };

    networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
  };
}
