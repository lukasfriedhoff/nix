{
  config,
  lib,
  pkgs,
  secrets ? { },
  ...
}:

let
  cfg = config.lukasf.atticCache;
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

  primaryRoot = secrets.primary or secrets.root or null;
  resolveSecret =
    path:
    if path == null then
      null
    else if lib.hasPrefix "/" path then
      path
    else if primaryRoot != null then
      "${primaryRoot}/${path}"
    else
      throw "lukasf.atticCache: relative secret '${path}' requires secrets.primary/root";

  cacheUrl = "${cfg.serverUrl}/${cfg.cacheName}?priority=${toString cfg.priority}";
  serverSettings = {
    listen = cfg.listenAddress;
    "api-endpoint" = cfg.serverUrl;
    chunking = {
      "nar-size-threshold" = 65536;
      "min-size" = 16384;
      "avg-size" = 65536;
      "max-size" = 262144;
    };
    database.url = cfg.databaseUrl;
    storage = {
      type = "local";
      path = cfg.storagePath;
    };
  };
  serverConfigFile = (pkgs.formats.toml { }).generate "attic-server.toml" serverSettings;
in
{
  options.lukasf.atticCache = {
    enable = mkEnableOption "Attic binary cache integration";

    serve = mkOption {
      type = types.bool;
      default = false;
      description = "Run the Attic cache server on this host.";
    };

    configureClient = mkOption {
      type = types.bool;
      default = true;
      description = "Configure this host to use the Attic cache as a Nix substituter.";
    };

    serverUrl = mkOption {
      type = types.str;
      default = "https://attic.h4xx.io";
      description = "Public Attic server URL.";
    };

    cacheName = mkOption {
      type = types.str;
      default = "homelab";
      description = "Attic cache name.";
    };

    publicKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Attic cache public key from `attic cache info`.";
    };

    priority = mkOption {
      type = types.int;
      default = 30;
      description = "Substituter priority advertised to Nix.";
    };

    environmentFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "SOPS file containing ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64.";
    };

    tokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Optional SOPS file containing an Attic client token for upload jobs.";
    };

    listenAddress = mkOption {
      type = types.str;
      default = "0.0.0.0:8080";
      description = "Attic listen address.";
    };

    port = mkOption {
      type = types.port;
      default = 8080;
      description = "Attic HTTP port to open when openFirewall is enabled.";
    };

    storagePath = mkOption {
      type = types.path;
      default = "/var/lib/atticd/storage";
      description = "Local Attic storage path.";
    };

    databaseUrl = mkOption {
      type = types.str;
      default = "sqlite:///var/lib/atticd/server.db?mode=rwc";
      description = "Attic database URL.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      description = "Open the Attic HTTP port in the firewall.";
    };

    postBuildUpload = {
      enable = mkOption {
        type = types.bool;
        default = false;
        description = "Upload locally completed Nix builds to this Attic cache with a Nix post-build hook.";
      };

      serverAlias = mkOption {
        type = types.str;
        default = "local";
        description = "Attic client server alias used by the upload hook.";
      };

      tokenSubject = mkOption {
        type = types.str;
        default = "nix-post-build-hook";
        description = "Subject used for the generated Attic upload token.";
      };

      tokenValidity = mkOption {
        type = types.str;
        default = "10y";
        description = "Validity period for the generated Attic upload token.";
      };

      uploadJobs = mkOption {
        type = types.ints.positive;
        default = 2;
        description = "Maximum number of parallel Attic upload jobs.";
      };

      stateDir = mkOption {
        type = types.str;
        default = "/var/lib/attic-upload";
        description = "State directory for the generated token and Attic client config.";
      };

      uploadInterval = mkOption {
        type = types.str;
        default = "1min";
        description = "Interval for draining queued post-build upload paths.";
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    (
      let
        postBuildStateDir = cfg.postBuildUpload.stateDir;
        postBuildTokenFile = "${postBuildStateDir}/token";
        postBuildConfigHome = "${postBuildStateDir}/config";
        postBuildQueueDir = "${postBuildStateDir}/queue";
        postBuildCache = "${cfg.postBuildUpload.serverAlias}:${cfg.cacheName}";
        postBuildLogin = pkgs.writeShellScript "attic-post-build-login" ''
          set -euo pipefail

          install -d -m 0700 \
            ${lib.escapeShellArg postBuildStateDir} \
            ${lib.escapeShellArg postBuildConfigHome} \
            ${lib.escapeShellArg postBuildQueueDir}

          if [ ! -s ${lib.escapeShellArg postBuildTokenFile} ]; then
            token_tmp="$(mktemp ${lib.escapeShellArg postBuildTokenFile}.XXXXXX)"
            set -a
            . ${config.sops.secrets."attic-server-env".path}
            set +a
            HOME=${lib.escapeShellArg postBuildStateDir} \
              ${pkgs.attic-server}/bin/atticadm make-token \
                --config ${serverConfigFile} \
                --sub ${lib.escapeShellArg cfg.postBuildUpload.tokenSubject} \
                --validity ${lib.escapeShellArg cfg.postBuildUpload.tokenValidity} \
                --pull ${lib.escapeShellArg cfg.cacheName} \
                --push ${lib.escapeShellArg cfg.cacheName} \
                > "$token_tmp"
            chmod 0400 "$token_tmp"
            mv "$token_tmp" ${lib.escapeShellArg postBuildTokenFile}
          fi

          HOME=${lib.escapeShellArg postBuildStateDir} \
          XDG_CONFIG_HOME=${lib.escapeShellArg postBuildConfigHome} \
            ${getExe pkgs.attic-client} login \
              ${lib.escapeShellArg cfg.postBuildUpload.serverAlias} \
              ${lib.escapeShellArg cfg.serverUrl} \
              "$(${pkgs.coreutils}/bin/tr -d '\r\n' < ${lib.escapeShellArg postBuildTokenFile})" \
              >/dev/null
        '';
        postBuildHook = pkgs.writeShellScript "attic-post-build-upload" ''
          set -eu

          if [ -z "''${OUT_PATHS:-}" ]; then
            exit 0
          fi

          install -d -m 0700 ${lib.escapeShellArg postBuildQueueDir}

          queue_file="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg postBuildQueueDir}/paths.XXXXXXXXXX)"
          printf '%s\n' $OUT_PATHS > "$queue_file"
          chmod 0600 "$queue_file"
        '';
        postBuildUploader = pkgs.writeShellScript "attic-post-build-drain" ''
          set -euo pipefail

          if [ ! -s ${lib.escapeShellArg postBuildTokenFile} ]; then
            exit 0
          fi

          install -d -m 0700 ${lib.escapeShellArg postBuildQueueDir}

          mapfile -t queue_files < <(
            ${pkgs.findutils}/bin/find ${lib.escapeShellArg postBuildQueueDir} \
              -maxdepth 1 \
              -type f \
              -name 'paths.*' \
              -print \
              | ${pkgs.coreutils}/bin/sort
          )

          if [ "''${#queue_files[@]}" -eq 0 ]; then
            exit 0
          fi

          batch_file="$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg postBuildStateDir}/batch.XXXXXXXXXX)"
          trap 'rm -f "$batch_file"' EXIT

          ${pkgs.coreutils}/bin/cat "''${queue_files[@]}" \
            | ${pkgs.coreutils}/bin/sort -u \
            > "$batch_file"

          export HOME=${lib.escapeShellArg postBuildStateDir}
          export XDG_CONFIG_HOME=${lib.escapeShellArg postBuildConfigHome}

          if ${getExe pkgs.attic-client} push \
            --stdin \
            --jobs ${toString cfg.postBuildUpload.uploadJobs} \
            ${lib.escapeShellArg postBuildCache} \
            < "$batch_file" \
            >> /var/log/attic-post-build-upload.log 2>&1
          then
            rm -f "''${queue_files[@]}"
          fi
        '';
      in
      {
        environment.systemPackages = [ pkgs.attic-client ];

        assertions = [
          {
            assertion = cfg.postBuildUpload.enable -> cfg.environmentFile != null;
            message = "lukasf.atticCache.postBuildUpload requires lukasf.atticCache.environmentFile for token signing.";
          }
        ];

        systemd.services.attic-post-build-login = mkIf cfg.postBuildUpload.enable {
          description = "Prepare Attic credentials for Nix post-build uploads";
          before = [ "nix-daemon.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = postBuildLogin;
          };
        };

        systemd.services.attic-post-build-drain = mkIf cfg.postBuildUpload.enable {
          description = "Drain queued Nix post-build uploads to Attic";
          after = [
            "network-online.target"
            "attic-post-build-login.service"
          ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = postBuildUploader;
          };
        };

        systemd.timers.attic-post-build-drain = mkIf cfg.postBuildUpload.enable {
          description = "Periodically drain queued Nix post-build uploads to Attic";
          wantedBy = [ "timers.target" ];
          timerConfig = {
            OnBootSec = "2min";
            OnUnitActiveSec = cfg.postBuildUpload.uploadInterval;
            Unit = "attic-post-build-drain.service";
          };
        };

        nix.settings.post-build-hook = mkIf cfg.postBuildUpload.enable postBuildHook;
      }
    )

    (mkIf ((cfg.serve || cfg.postBuildUpload.enable) && cfg.environmentFile != null) {
      sops.secrets."attic-server-env" = {
        sopsFile = resolveSecret cfg.environmentFile;
        format = "dotenv";
        mode = "0400";
        owner = "root";
      };
    })

    (mkIf cfg.serve {
      assertions = [
        {
          assertion = cfg.environmentFile != null;
          message = "lukasf.atticCache.environmentFile must point at an Attic server environment secret.";
        }
      ];

      services.atticd = {
        enable = true;
        environmentFile = config.sops.secrets."attic-server-env".path;
        settings = serverSettings;
      };

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [ cfg.port ];
    })

    (mkIf (cfg.configureClient && cfg.publicKey != null) {
      nix.settings = {
        substituters = lib.mkBefore [ cacheUrl ];
        trusted-public-keys = lib.mkAfter [ cfg.publicKey ];
      };
    })

    (mkIf (cfg.tokenFile != null) {
      sops.secrets."attic-client-token" = {
        sopsFile = resolveSecret cfg.tokenFile;
        format = "binary";
        mode = "0400";
        owner = "root";
      };

      environment.etc."attic/login-homelab-cache".source =
        pkgs.writeShellScript "attic-login-homelab-cache" ''
          set -euo pipefail
          token="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "${config.sops.secrets."attic-client-token".path}")"
          exec ${getExe pkgs.attic-client} login ${lib.escapeShellArg cfg.cacheName} ${lib.escapeShellArg cfg.serverUrl} "$token"
        '';
    })
  ]);
}
