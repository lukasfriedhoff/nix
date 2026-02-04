{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.wireguard.homelab;
  shared = config.shared.vpn.homelab;
  iface = "wg-homelab";
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
      default = [ "192.168.88.1" ];
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
  };

  config = lib.mkMerge [
    {
      lukasf.wireguard.homelab = {
        dns = lib.mkDefault shared.dns;
        peerPublicKey = lib.mkDefault shared.peerPublicKey;
        allowedIPs = lib.mkDefault shared.allowedIPs;
        persistentKeepalive = lib.mkDefault shared.persistentKeepalive;
        mtu = lib.mkDefault shared.mtu;
      };
    }
    (lib.mkIf cfg.enable (
      let
        setDnsScript = pkgs.writeShellScript "wg-homelab-set-dns" ''
          set -euo pipefail
          iface="$1"
          shift
          ${pkgs.systemd}/bin/resolvectl dns "$iface" "$@"
        '';

        setDomainScript = pkgs.writeShellScript "wg-homelab-set-domain" ''
          set -euo pipefail
          iface="$1"
          domain_file="$2"
          domain="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$domain_file")"
          if [ -z "$domain" ]; then
            echo "wg-homelab: domain file $domain_file is empty" >&2
            exit 1
          fi
          ${pkgs.systemd}/bin/resolvectl domain "$iface" "~$domain"
        '';

        setEndpointScript = pkgs.writeShellScript "wg-homelab-set-endpoint" ''
          set -euo pipefail
          iface="$1"
          endpoint_file="$2"
          endpoint="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$endpoint_file")"
          if [ -z "$endpoint" ]; then
            echo "wg-homelab: endpoint file $endpoint_file is empty" >&2
            exit 1
          fi
          ${pkgs.wireguard-tools}/bin/wg set "$iface" peer ${cfg.peerPublicKey} persistent-keepalive ${toString cfg.persistentKeepalive} endpoint "$endpoint"
        '';
      in
      {
        networking.wireguard.interfaces.${iface} = {
          privateKeyFile = cfg.privateKeyFile;
          ips = [ cfg.address ];
          listenPort = 0;
          mtu = cfg.mtu;
          postSetup = [
            "${setDnsScript} ${iface} ${lib.concatStringsSep " " cfg.dns}"
            "${setDomainScript} ${iface} ${cfg.dnsDomainFile}"
            "${setEndpointScript} ${iface} ${cfg.endpointFile}"
          ];
          peers = [
            {
              publicKey = cfg.peerPublicKey;
              allowedIPs = cfg.allowedIPs;
            }
          ];
        };
      }
    ))
  ];
}
