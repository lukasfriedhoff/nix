{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.vxlanLegs;
  inherit (lib)
    concatStringsSep
    mapAttrs'
    mkIf
    mkOption
    nameValuePair
    types
    ;

  legs = lib.attrValues cfg;

  legModule =
    { name, ... }:
    {
      options = {
        interfaceName = mkOption {
          type = types.strMatching "[a-zA-Z0-9_.-]{1,15}";
          default = name;
          description = "Linux interface name (kernel limit: 15 characters).";
        };
        vni = mkOption {
          type = types.ints.between 1 16777215;
          description = "VXLAN network identifier; must match the remote VTEP.";
        };
        localAddress = mkOption {
          type = types.str;
          description = "Local VTEP IPv4 address (an address configured on this host).";
        };
        remoteAddress = mkOption {
          type = types.str;
          description = "Remote VTEP IPv4 address: a single unicast peer, no multicast group.";
        };
        port = mkOption {
          type = types.port;
          default = 4789;
          description = "VXLAN UDP port, used in both directions.";
        };
        mtu = mkOption {
          type = types.int;
          default = 1400;
          description = ''
            Interface MTU. 1400 leaves room for the 50-byte VXLAN overhead
            inside the 1476-byte WireGuard site-to-site path.
          '';
        };
        allowedUDPPorts = mkOption {
          type = types.listOf types.port;
          default = [
            5353
            5540
          ];
          description = "UDP ports accepted on the leg itself (mDNS 5353, Matter 5540).";
        };
        allowedTCPPorts = mkOption {
          type = types.listOf types.port;
          default = [ ];
          description = "TCP ports accepted on the leg itself.";
        };
      };
    };
in
{
  options.homelab.vxlanLegs = mkOption {
    type = types.attrsOf (types.submodule legModule);
    default = { };
    example = {
      vxlan-iot-kiosk = {
        vni = 12;
        localAddress = "10.3.30.31";
        remoteAddress = "10.1.30.1";
      };
    };
    description = ''
      Point-to-point VXLAN "legs": a plain, UNBRIDGED layer-2 interface on this
      host that terminates a VLAN of a remote site (e.g. the kiosk IoT VLAN,
      where the far router puts the VXLAN into its bridge with that VLAN's
      pvid). hostNetwork services such as matter-server and Home Assistant
      zeroconf then see the remote mDNS and IPv6 link-local traffic.

      The leg carries no IPv4, ignores router advertisements, never forwards
      and is never bridged, so the two sites' broadcast domains stay separate.
      Merging two routers' VLANs with EoIP instead stormed the kiosk router on
      2026-10-28; this is the deliberately narrower replacement.
    '';
  };

  config = mkIf (cfg != { }) {
    assertions = map (leg: {
      assertion = leg.localAddress != leg.remoteAddress;
      message = "homelab.vxlanLegs.${leg.interfaceName}: local and remote VTEP addresses must differ.";
    }) legs;

    systemd.services = mapAttrs' (
      name: leg:
      nameValuePair "vxlan-leg-${name}" {
        description = "VXLAN L2 leg ${leg.interfaceName} (VNI ${toString leg.vni}) to ${leg.remoteAddress}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          pkgs.iproute2
          pkgs.procps
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ip link del dev ${leg.interfaceName} 2>/dev/null || true
          ip link add ${leg.interfaceName} type vxlan id ${toString leg.vni} \
            local ${leg.localAddress} remote ${leg.remoteAddress} \
            dstport ${toString leg.port} nolearning
          # Link-local IPv6 only: no SLAAC from the remote router's RAs, no
          # routing for either family, no IPv4 at all.
          sysctl -qw \
            net.ipv6.conf.${leg.interfaceName}.accept_ra=0 \
            net.ipv6.conf.${leg.interfaceName}.autoconf=0 \
            net.ipv6.conf.${leg.interfaceName}.forwarding=0 \
            net.ipv4.conf.${leg.interfaceName}.forwarding=0
          ip link set ${leg.interfaceName} mtu ${toString leg.mtu} up
        '';
        preStop = "ip link del dev ${leg.interfaceName} 2>/dev/null || true";
      }
    ) cfg;

    networking.firewall = {
      interfaces = mapAttrs' (
        _: leg:
        nameValuePair leg.interfaceName {
          inherit (leg) allowedUDPPorts allowedTCPPorts;
        }
      ) cfg;
    }
    // (
      if config.networking.nftables.enable then
        {
          extraInputRules = concatStringsSep "\n" (
            map (leg: "ip saddr ${leg.remoteAddress} udp dport ${toString leg.port} accept") legs
          );
        }
      else
        {
          extraCommands = concatStringsSep "\n" (
            map (
              leg:
              "iptables -A nixos-fw -p udp -s ${leg.remoteAddress} --dport ${toString leg.port} -j nixos-fw-accept"
            ) legs
          );
        }
    );
  };
}
