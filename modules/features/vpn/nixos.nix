{
  lib,
  ...
}:

{
  options.shared.vpn.homelab = {
    peerPublicKey = lib.mkOption {
      type = lib.types.str;
      default = "gSkqlSSX1RfMiyG99bcqtwK58/h/YalzKf/zuNpL7mc=";
      description = "WireGuard peer public key for the homelab VPN.";
    };
    dns = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "10.1.30.1" ];
      description = "DNS servers pushed to homelab VPN clients.";
    };
    allowedIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "10.1.0.0/16"
        "10.0.10.0/23"
        "192.168.88.0/24"
        "172.16.0.0/16"
      ];
      description = "Networks reachable over the homelab WireGuard peer.";
    };
    persistentKeepalive = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 25;
      description = "Persistent keepalive interval in seconds.";
    };
    mtu = lib.mkOption {
      type = lib.types.ints.u16;
      default = 1476;
      description = "WireGuard MTU to use on the client interface.";
    };
  };
}
