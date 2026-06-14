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

  localHostNames = [
    config.networking.hostName
  ]
  ++ lib.optional (
    config.networking.domain != null && config.networking.domain != ""
  ) "${config.networking.hostName}.${config.networking.domain}";

  skipLocalBuilder = cfg.skipLocalBuilder && lib.elem cfg.hostName localHostNames;
in
{
  options.lukasf.remoteBuilds = {
    enable = mkEnableOption "distributed builds via the srv3 builder" // {
      default = !workSystem;
    };

    hostName = mkOption {
      type = types.str;
      default = "srv3.lab.h4xx.io";
      description = "Logical builder hostname used by Nix.";
    };

    sshHostName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Actual SSH hostname for the builder. Defaults to hostName.";
    };

    sshPort = mkOption {
      type = types.port;
      default = 22;
      description = "SSH port used for the builder connection.";
    };

    sshUser = mkOption {
      type = types.str;
      default = "root";
      description = "SSH user used for remote builds.";
    };

    sshKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional SSH private key path for the builder connection (must be a local path, not a store path).";
    };

    publicHostKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional base64-encoded SSH host key for the builder (base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub).";
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

    connectTimeout = mkOption {
      type = types.int;
      default = 5;
      description = "SSH connection timeout in seconds. Lower values provide faster fallback to local builds when builder is unavailable.";
    };

    fallbackToLocal = mkOption {
      type = types.bool;
      default = true;
      description = "Allow local builds when remote builder is unavailable (sets max-jobs > 0).";
    };

    localMaxJobs = mkOption {
      type = types.ints.unsigned;
      default = 4;
      description = "Max parallel jobs for local builds when fallback is enabled.";
    };

    skipLocalBuilder = mkOption {
      type = types.bool;
      default = true;
      description = "Skip configuring a remote builder when the builder host resolves to this machine.";
    };
  };

  config = mkIf cfg.enable (
    lib.mkMerge [
      {
        nix = {
          distributedBuilds = lib.mkDefault (!skipLocalBuilder);
          settings = {
            builders-use-substitutes = true;
            # Allow local builds as fallback when remote builder is unavailable
            max-jobs = lib.mkIf cfg.fallbackToLocal cfg.localMaxJobs;
          };
        };
      }
      (mkIf (!skipLocalBuilder) {
        nix.buildMachines = [
          (
            {
              inherit (cfg) hostName;
              inherit (cfg) system;
              inherit (cfg) sshUser;
              inherit (cfg) maxJobs;
              inherit (cfg) speedFactor;
              inherit (cfg) supportedFeatures;
              inherit (cfg) mandatoryFeatures;
            }
            // optionalAttrs (cfg.sshKeyFile != null) {
              sshKey = cfg.sshKeyFile;
            }
            // optionalAttrs (cfg.publicHostKey != null) {
              inherit (cfg) publicHostKey;
            }
          )
        ];

        # Configure SSH with connection timeout for the builder
        programs.ssh.extraConfig = ''
          Host ${cfg.hostName}
            HostName ${if cfg.sshHostName != null then cfg.sshHostName else cfg.hostName}
            Port ${toString cfg.sshPort}
            User ${cfg.sshUser}
            IdentitiesOnly yes
            StrictHostKeyChecking yes
            ${lib.optionalString (cfg.sshKeyFile != null) "IdentityFile ${cfg.sshKeyFile}"}
            ConnectTimeout ${toString cfg.connectTimeout}
            ServerAliveInterval 10
            ServerAliveCountMax 3
        '';
      })
    ]
  );
}
