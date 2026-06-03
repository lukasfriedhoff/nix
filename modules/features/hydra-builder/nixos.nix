{
  config,
  lib,
  pkgs,
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

  jobsetSubmodule = types.submodule {
    options = {
      flake = mkOption {
        type = types.str;
        description = "Flake URI for this jobset.";
      };
      description = mkOption {
        type = types.str;
        default = "";
      };
      checkInterval = mkOption {
        type = types.int;
        default = 3600;
        description = "Seconds between evaluation checks.";
      };
      schedulingShares = mkOption {
        type = types.int;
        default = 1;
      };
      keepNr = mkOption {
        type = types.int;
        default = 3;
        description = "Number of builds to keep per job.";
      };
    };
  };

  projectSubmodule = types.submodule {
    options = {
      displayName = mkOption {
        type = types.str;
        default = "";
      };
      description = mkOption {
        type = types.str;
        default = "";
      };
      jobsets = mkOption {
        type = types.attrsOf jobsetSubmodule;
        default = { };
      };
    };
  };

  bootstrapScript =
    let
      baseUrl = "http://localhost:${toString cfg.port}";
      projectsJson = lib.mapAttrsToList (
        projectName: project:
        lib.mapAttrsToList (jobsetName: jobset: {
          inherit projectName jobsetName;
          projectPayload = builtins.toJSON {
            displayname = project.displayName;
            description = project.description;
            enabled = "1";
            visible = "1";
          };
          jobsetPayload = builtins.toJSON {
            type = 1;
            flake = jobset.flake;
            description = jobset.description;
            checkinterval = jobset.checkInterval;
            schedulingshares = jobset.schedulingShares;
            keepnr = jobset.keepNr;
            enabled = 1;
            visible = true;
          };
        }) project.jobsets
      ) cfg.declarativeProjects;
      flatEntries = lib.flatten projectsJson;
    in
    pkgs.writeShellScript "hydra-bootstrap" ''
      set -euo pipefail

      HYDRA_URL="${baseUrl}"
      ADMIN_PASSWORD="$(cat "$CREDENTIALS_DIRECTORY/admin-password")"

      # Create/update admin user directly in the Hydra database.
      ${cfg.package}/bin/hydra-create-user admin \
        --full-name "Admin" \
        --email-address "admin@localhost" \
        --password "$ADMIN_PASSWORD" \
        --role admin

      echo "Admin user ensured"

      # Wait for the Hydra web server (up to 150s).
      for i in $(seq 1 30); do
        ${pkgs.curl}/bin/curl -sf "$HYDRA_URL/api/projects" > /dev/null 2>&1 && break
        echo "Waiting for Hydra web server ($i/30)..."
        sleep 5
        [ "$i" = "30" ] && { echo "Hydra web server not available"; exit 1; }
      done

      # Login and capture the session cookie.
      COOKIE_JAR="$(${pkgs.coreutils}/bin/mktemp)"
      trap '${pkgs.coreutils}/bin/rm -f "$COOKIE_JAR"' EXIT

      ${pkgs.curl}/bin/curl -sf \
        -c "$COOKIE_JAR" \
        -X POST \
        -H "Referer: $HYDRA_URL/" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -H "Accept: application/json" \
        --data-urlencode "username=admin" \
        --data-urlencode "password=$ADMIN_PASSWORD" \
        "$HYDRA_URL/login" > /dev/null

      echo "Logged in to Hydra"

      ${lib.concatMapStrings (
        entry: # sh
        ''
          echo "Ensuring project '${entry.projectName}'..."
          ${pkgs.curl}/bin/curl -sf \
            -b "$COOKIE_JAR" \
            -X PUT \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            --data ${lib.escapeShellArg entry.projectPayload} \
            "$HYDRA_URL/project/${entry.projectName}" > /dev/null

          echo "Ensuring jobset '${entry.projectName}/${entry.jobsetName}'..."
          ${pkgs.curl}/bin/curl -sf \
            -b "$COOKIE_JAR" \
            -X PUT \
            -H "Content-Type: application/json" \
            -H "Accept: application/json" \
            --data ${lib.escapeShellArg entry.jobsetPayload} \
            "$HYDRA_URL/jobset/${entry.projectName}/${entry.jobsetName}" > /dev/null
        '') flatEntries}

      echo "Hydra bootstrap complete"
    '';
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

    package = mkOption {
      type = types.package;
      default = pkgs.hydra.overrideAttrs (_: {
        doCheck = false;
      });
      defaultText = "pkgs.hydra with checks disabled";
      description = "Hydra package to run.";
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

    adminPasswordFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to a file containing the Hydra admin password. Enables declarative bootstrap when set.";
    };

    declarativeProjects = mkOption {
      type = types.attrsOf projectSubmodule;
      default = { };
      description = "Projects and flake jobsets to ensure exist after startup (idempotent PUT).";
    };
  };

  config = mkIf cfg.enable {
    services.hydra = {
      enable = true;
      inherit (cfg) package;
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

    systemd.services.hydra-bootstrap = mkIf (cfg.adminPasswordFile != null) {
      description = "Bootstrap Hydra admin user and declarative projects/jobsets";
      after = [
        "hydra-init.service"
        "hydra-server.service"
      ];
      wants = [ "hydra-server.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "hydra";
        LoadCredential = "admin-password:${cfg.adminPasswordFile}";
        Environment = "HYDRA_DBI=${config.services.hydra.dbi}";
        ExecStart = bootstrapScript;
      };
    };
  };
}
