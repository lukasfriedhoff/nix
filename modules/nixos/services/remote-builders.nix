{
  config,
  lib,
  workSystem ? false,
  ...
}:

let
  cfg = config.lukasf.remoteBuilds;
  inherit (lib)
    mkIf
    mkOption
    mkEnableOption
    optionalAttrs
    types
    ;
in
{
  options.lukasf.remoteBuilds = {
    enable = mkOption {
      type = types.bool;
      default = !workSystem;
      description = "Enable distributed builds via the srv1 builder.";
    };

    hostName = mkOption {
      type = types.str;
      default = "srv1.h4xx.local";
      description = "Builder hostname (srv1).";
    };

    sshUser = mkOption {
      type = types.str;
      default = "root";
      description = "SSH user used for remote builds.";
    };

    sshKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Optional SSH private key for the builder connection.";
    };

    system = mkOption {
      type = types.str;
      default = "x86_64-linux";
      description = "System type of the builder.";
    };

    maxJobs = mkOption {
      type = types.ints.positive;
      default = 4;
      description = "Maximum parallel jobs on the builder.";
    };

    speedFactor = mkOption {
      type = types.ints.positive;
      default = 2;
      description = "Builder speed factor used by Nix scheduling.";
    };

    supportedFeatures = mkOption {
      type = types.listOf types.str;
      default = [
        "kvm"
        "big-parallel"
      ];
      description = "Features advertised by the builder.";
    };

    mandatoryFeatures = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Features required for jobs to be scheduled on the builder.";
    };
  };

  config = mkIf cfg.enable {
    nix = {
      distributedBuilds = true;
      settings.builders-use-substitutes = true;
      buildMachines = [
        (
          {
            hostName = cfg.hostName;
            system = cfg.system;
            sshUser = cfg.sshUser;
            maxJobs = cfg.maxJobs;
            speedFactor = cfg.speedFactor;
            supportedFeatures = cfg.supportedFeatures;
            mandatoryFeatures = cfg.mandatoryFeatures;
          }
          // optionalAttrs (cfg.sshKeyFile != null) {
            sshKey = cfg.sshKeyFile;
          }
        )
      ];
    };
  };
}
