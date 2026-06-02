{
  lib,
  config,
  pkgs,
  linuxUser ? null,
  ...
}:

let
  cfg = config.lukasf.wireguard.homelab;
  shared = config.shared.vpn.homelab;
  iface = "wg-homelab";
  defaultUser = linuxUser;
  userServiceName = "wireguard-${iface}";
  peerServiceName = "wireguard-${iface}-peer-${
    lib.replaceStrings [ "/" "=" ] [ "-" "\\x3d" ] cfg.peerPublicKey
  }";
  refreshServiceName = "${userServiceName}-refresh";
  sleepServiceName = "${userServiceName}-sleep";
in
{
  options.lukasf.wireguard.homelab = {
    enable = lib.mkEnableOption "WireGuard client for the MikroTik homelab tunnel";

    privateKeyFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to the private key file. Typically this is a decrypted SOPS secret,
        e.g. <literal>${config.secrets.primary or ""}/wireguard/homelab.key</literal>.
      '';
    };

    address = lib.mkOption {
      type = lib.types.str;
      default = "10.1.90.2/24";
      description = "IP address (with CIDR) assigned to this node inside the homelab WireGuard network.";
    };

    mtu = lib.mkOption {
      type = lib.types.ints.u16;
      default = 1384;
      description = "WireGuard MTU to use on the client interface.";
    };

    dns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "10.1.90.1" ];
      description = "Resolvers to push via resolvectl once the interface is up.";
    };

    dnsDomainFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a (secret) file containing the search domain, e.g. `h4xx.io`.";
    };

    endpointFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a (secret) file containing the WireGuard endpoint (`host:port`).";
    };

    peerPublicKey = lib.mkOption {
      type = lib.types.str;
      default = "gSkqlSSX1RfMiyG99bcqtwK58/h/YalzKf/zuNpL7mc=";
      description = "Public key of the MikroTik peer.";
    };

    persistentKeepalive = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 25;
      description = "Persistent keepalive interval in seconds.";
    };

    allowedIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "10.1.0.0/16"
        "10.0.10.0/23"
        "192.168.88.0/24"
        "172.16.0.0/16"
      ];
      description = "Networks reachable over the MikroTik VPN peer.";
    };

    endpointResolutionRetries = lib.mkOption {
      type = lib.types.str;
      default = "30";
      example = "15";
      description = ''
        Value for <literal>WG_ENDPOINT_RESOLUTION_RETRIES</literal>. Use
        <literal>infinity</literal> to keep retrying endpoint DNS resolution
        until network is available. A finite default avoids wedging the
        oneshot start path forever when DNS is unavailable after resume.
      '';
    };

    healthcheck = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable periodic reachability checks and self-healing restarts for the tunnel.";
      };

      target = lib.mkOption {
        type = lib.types.str;
        default = "10.1.90.1";
        description = "Reachability target over the VPN used by the health check.";
      };
    };

    userUnit = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Start the WireGuard tunnel from a user systemd unit instead of at boot.";
      };

      user = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = defaultUser;
        defaultText = if defaultUser != null then lib.literalExpression "linuxUser" else "null";
        description = "User allowed to manage the homelab WireGuard unit from their session.";
      };
    };
  };

  config = lib.mkMerge [
    {
      lukasf.wireguard.homelab = {
        dns = lib.mkDefault shared.dns;
        peerPublicKey = lib.mkDefault shared.peerPublicKey;
        allowedIPs = lib.mkDefault shared.allowedIPs;
        persistentKeepalive = lib.mkDefault shared.persistentKeepalive;
        mtu = lib.mkDefault shared.mtu;
        healthcheck.target = lib.mkDefault shared.healthcheckTarget;
      };

      assertions = [
        {
          assertion = (!cfg.userUnit.enable) || cfg.userUnit.user != null;
          message = "lukasf.wireguard.homelab.userUnit requires a user (set linuxUser or userUnit.user).";
        }
      ];
    }
    (lib.mkIf cfg.enable (
      let
        setDnsScript = pkgs.writeShellScript "wg-homelab-set-dns" ''
          set -euo pipefail
          iface="$1"
          shift
          for _ in $(seq 1 6); do
            if ${pkgs.systemd}/bin/resolvectl dns "$iface" "$@"; then
              exit 0
            fi
            sleep 2
          done
          echo "wg-homelab: failed to set DNS on $iface after retries" >&2
          exit 1
        '';

        setDomainScript = pkgs.writeShellScript "wg-homelab-set-domain" ''
          set -euo pipefail
          iface="$1"
          domain_file="$2"
          domain=""
          for _ in $(seq 1 20); do
            if [ -s "$domain_file" ]; then
              domain="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$domain_file")"
              [ -n "$domain" ] && break
            fi
            sleep 1
          done
          if [ -z "$domain" ]; then
            echo "wg-homelab: domain file $domain_file is empty" >&2
            exit 1
          fi
          for _ in $(seq 1 6); do
            if ${pkgs.systemd}/bin/resolvectl domain "$iface" "~$domain"; then
              exit 0
            fi
            sleep 2
          done
          echo "wg-homelab: failed to set domain on $iface after retries" >&2
          exit 1
        '';

        setEndpointScript = pkgs.writeShellScript "wg-homelab-set-endpoint" ''
          set -euo pipefail
          iface="$1"
          endpoint_file="$2"
          endpoint=""
          for _ in $(seq 1 20); do
            if [ -s "$endpoint_file" ]; then
              endpoint="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$endpoint_file")"
              [ -n "$endpoint" ] && break
            fi
            sleep 1
          done
          if [ -z "$endpoint" ]; then
            echo "wg-homelab: endpoint file $endpoint_file is empty" >&2
            exit 1
          fi

          endpoint_host="''${endpoint%:*}"
          endpoint_port="''${endpoint##*:}"
          if [ "$endpoint_host" = "$endpoint_port" ]; then
            echo "wg-homelab: endpoint '$endpoint' must be host:port" >&2
            exit 1
          fi

          retries="''${WG_ENDPOINT_RESOLUTION_RETRIES:-20}"
          attempt=0
          while true; do
            if ${lib.getExe' pkgs.getent "getent"} ahostsv4 "$endpoint_host" >/dev/null 2>&1 || \
               ${lib.getExe' pkgs.getent "getent"} ahostsv6 "$endpoint_host" >/dev/null 2>&1; then
              break
            fi
            attempt=$((attempt + 1))
            if [ "$retries" != "infinity" ] && [ "$attempt" -ge "$retries" ]; then
              echo "wg-homelab: cannot resolve endpoint host '$endpoint_host' after $attempt tries" >&2
              exit 1
            fi
            sleep 2
          done

          ${pkgs.wireguard-tools}/bin/wg set "$iface" peer ${cfg.peerPublicKey} persistent-keepalive ${toString cfg.persistentKeepalive} endpoint "$endpoint"
        '';

        refreshScript = pkgs.writeShellScript "wg-homelab-refresh" ''
          set -euo pipefail

          if ! ${pkgs.iproute2}/bin/ip link show dev ${iface} >/dev/null 2>&1; then
            # Recover from skipped starts (e.g. secret not present earlier).
            ${pkgs.systemd}/bin/systemctl start ${userServiceName}.service || true
            for _ in $(seq 1 10); do
              if ${pkgs.iproute2}/bin/ip link show dev ${iface} >/dev/null 2>&1; then
                break
              fi
              sleep 1
            done
          fi

          if ! ${pkgs.iproute2}/bin/ip link show dev ${iface} >/dev/null 2>&1; then
            exit 0
          fi

          ${setEndpointScript} ${iface} ${cfg.endpointFile}
          ${setDnsScript} ${iface} ${lib.concatStringsSep " " cfg.dns} || true
          ${setDomainScript} ${iface} ${cfg.dnsDomainFile} || true

          ${lib.optionalString cfg.healthcheck.enable ''
            if ! ${pkgs.iputils}/bin/ping -I ${iface} -c 1 -W 2 ${cfg.healthcheck.target} >/dev/null 2>&1; then
              ${pkgs.systemd}/bin/systemctl restart ${userServiceName}.service || true
              ${setEndpointScript} ${iface} ${cfg.endpointFile} || true
              ${setDnsScript} ${iface} ${lib.concatStringsSep " " cfg.dns} || true
              ${setDomainScript} ${iface} ${cfg.dnsDomainFile} || true
            fi
          ''}
        '';

        sleepScript = pkgs.writeShellScript "wg-homelab-sleep" ''
          set -euo pipefail
          state_file="/run/${userServiceName}.was-active"
          if ${pkgs.systemd}/bin/systemctl is-active --quiet ${userServiceName}.service; then
            touch "$state_file"
            ${pkgs.systemd}/bin/systemctl stop ${userServiceName}.service
          else
            rm -f "$state_file"
          fi
        '';

        resumeScript = pkgs.writeShellScript "wg-homelab-resume" ''
          set -euo pipefail
          state_file="/run/${userServiceName}.was-active"
          if [ -f "$state_file" ]; then
            ${pkgs.systemd}/bin/systemctl --no-block start ${userServiceName}.service || true
            ${pkgs.systemd}/bin/systemctl --no-block start ${refreshServiceName}.service || true
          fi
          rm -f "$state_file"
        '';
      in
      {
        networking.wireguard.interfaces.${iface} = {
          inherit (cfg) privateKeyFile;
          ips = [ cfg.address ];
          listenPort = 0;
          inherit (cfg) mtu;
          postSetup = [
            "${setEndpointScript} ${iface} ${cfg.endpointFile} || true"
            "${setDnsScript} ${iface} ${lib.concatStringsSep " " cfg.dns} || true"
            "${setDomainScript} ${iface} ${cfg.dnsDomainFile} || true"
          ];
          peers = [
            {
              publicKey = cfg.peerPublicKey;
              inherit (cfg) allowedIPs;
            }
          ];
        };

        systemd.services.${userServiceName} = {
          wants = [
            "network-online.target"
          ];
          after = [
            "network-online.target"
          ];
          wantedBy = lib.mkIf cfg.userUnit.enable (lib.mkForce [ ]);
          unitConfig = {
            ConditionPathExists = cfg.privateKeyFile;
            StartLimitBurst = 6;
            StartLimitIntervalSec = "5min";
          };
          serviceConfig = {
            Environment = [ "WG_ENDPOINT_RESOLUTION_RETRIES=${cfg.endpointResolutionRetries}" ];
            Restart = "on-failure";
            RestartSec = "30s";
          };
        };

        systemd.services.${refreshServiceName} = {
          description = "Refresh homelab WireGuard endpoint/DNS settings";
          wants = [
            "${userServiceName}.service"
            "network-online.target"
          ];
          after = [
            "${userServiceName}.service"
            "network-online.target"
          ];
          serviceConfig = {
            Type = "oneshot";
            Environment = [ "WG_ENDPOINT_RESOLUTION_RETRIES=${cfg.endpointResolutionRetries}" ];
            ExecStart = refreshScript;
          };
        };

        # When the base interface is skipped (e.g. missing secret during activation),
        # skip peer application as well to avoid a failing switch transaction.
        systemd.services.${peerServiceName}.unitConfig.ConditionPathExists = "/sys/class/net/${iface}";

        systemd.timers.${refreshServiceName} = lib.mkIf (!cfg.userUnit.enable) {
          wantedBy = [ "timers.target" ];
          timerConfig = {
            Unit = "${refreshServiceName}.service";
            OnBootSec = "2min";
            OnUnitActiveSec = "3min";
            AccuracySec = "30s";
            RandomizedDelaySec = "20s";
          };
        };

        systemd.services.${sleepServiceName} = {
          description = "Homelab WireGuard suspend/resume handling";
          before = [ "sleep.target" ];
          wantedBy = [ "sleep.target" ];
          unitConfig.StopWhenUnneeded = true;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = sleepScript;
            ExecStop = resumeScript;
          };
        };

        systemd.targets.${userServiceName} = lib.mkIf cfg.userUnit.enable {
          wantedBy = lib.mkForce [ ];
        };

        systemd.user.services.${userServiceName} = lib.mkIf cfg.userUnit.enable {
          description = "WireGuard Tunnel - ${iface} (user)";
          after = [ "default.target" ];
          wants = [ ];
          wantedBy = [ "default.target" ];
          unitConfig.ConditionUser = cfg.userUnit.user;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${pkgs.systemd}/bin/systemctl --no-block start ${userServiceName}.service";
            ExecStop = "${pkgs.systemd}/bin/systemctl stop ${userServiceName}.service";
          };
        };

        security.polkit.extraConfig = lib.mkIf cfg.userUnit.enable (
          lib.mkAfter ''
            polkit.addRule(function(action, subject) {
              if (action.id == "org.freedesktop.systemd1.manage-units" &&
                  subject.user == "${cfg.userUnit.user}" &&
                  action.lookup("unit") == "${userServiceName}.service" &&
                  ["start", "stop", "restart", "try-restart", "reload-or-restart", "reset-failed"].indexOf(action.lookup("verb")) >= 0) {
                return polkit.Result.YES;
              }
            });
          ''
        );
      }
    ))
  ];
}
