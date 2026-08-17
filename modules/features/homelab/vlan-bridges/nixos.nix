{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.vlanBridges;
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

  nets = import ../../../../resources/homelab/networks.nix;
  mgmtVlan = nets.vlans.mgmt;
  mgmtGateway = mgmtVlan.gateway;
  taggedVlans = lib.filterAttrs (name: _: name != "mgmt") nets.vlans;

  bridgeName = vlan: "brvlan${toString vlan.id}";
  subInterface = vlan: "${cfg.uplink}.${toString vlan.id}";

  mgmtBridge = bridgeName mgmtVlan;
  serverBridge = bridgeName nets.vlans.server;
  storageBridge = bridgeName nets.vlans.storage;

  bondEnabled = cfg.bond != null;
in
{
  options.homelab.vlanBridges = {
    enable = mkEnableOption "libvirt-friendly VLAN bridges on the homelab uplink";

    uplink = mkOption {
      type = types.str;
      example = "eno1";
      description = ''
        Physical uplink (or bond) carrying the tagged homelab VLANs.
        The untagged management VLAN is bridged onto ${mgmtBridge}.
      '';
    };

    mgmtMac = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "0c:c4:7a:6c:38:02";
      description = ''
        MAC address assigned to the management bridge so the DHCP
        reservation keeps matching the physical NIC.
      '';
    };

    bond = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            members = mkOption {
              type = types.listOf types.str;
              description = "Physical interfaces enslaved to the bond uplink.";
            };
            mode = mkOption {
              type = types.str;
              default = "active-backup";
              description = "Bonding mode.";
            };
            primary = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Preferred active member in active-backup mode.";
            };
            miimon = mkOption {
              type = types.str;
              default = "100";
              description = "MII link monitoring interval in milliseconds.";
            };
          };
        }
      );
      default = null;
      description = ''
        When set, the uplink is created as a bond over the given members
        instead of using a plain NIC.
      '';
    };

    pinBridgeMac = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Pin the management bridge (and bond, if any) MAC via systemd
        netdev units in addition to networking.interfaces.macAddress.
      '';
    };

    routeMetrics = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Apply the networkd route policy: RouteMetric 100/200/300 on
        ${mgmtBridge}/${serverBridge}/${storageBridge}, a metric-100
        default route via the management gateway, and static routes for
        mgmtRoutedNetworks. Disable to keep a host on the minimal
        DHCP-only behavior.
      '';
    };

    dhcpBridges = mkOption {
      type = types.listOf types.str;
      default = [
        serverBridge
        storageBridge
      ];
      description = ''
        Bridges (besides the management bridge, which always uses DHCP)
        that request a DHCP lease.
      '';
    };

    mgmtRoutedNetworks = mkOption {
      type = types.listOf types.str;
      default = [ "10.1.90.0/24" ];
      description = ''
        Networks that are only reachable via the management gateway and
        need an explicit route (applied when routeMetrics is enabled).
      '';
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = !bondEnabled || cfg.bond.members != [ ];
          message = "homelab.vlanBridges.bond.members must not be empty.";
        }
        {
          assertion = !cfg.pinBridgeMac || cfg.mgmtMac != null;
          message = "homelab.vlanBridges.pinBridgeMac requires mgmtMac to be set.";
        }
      ];

      networking = {
        useNetworkd = true;
        networkmanager.enable = false;
        defaultGateway = lib.mkForce null;
        nameservers = [ mgmtGateway ];
        hosts."127.0.0.2" = lib.mkForce [ ];

        vlans = lib.mapAttrs' (
          _: vlan:
          lib.nameValuePair (subInterface vlan) {
            inherit (vlan) id;
            interface = cfg.uplink;
          }
        ) taggedVlans;

        # Libvirt-friendly bridges for each VLAN (mgmt untagged on ${mgmtBridge}).
        bridges =
          lib.mapAttrs' (
            _: vlan: lib.nameValuePair (bridgeName vlan) { interfaces = [ (subInterface vlan) ]; }
          ) taggedVlans
          // {
            ${mgmtBridge}.interfaces = [ cfg.uplink ];
          };

        interfaces =
          # Bring VLAN subinterfaces up even without an IP so bridges attach cleanly.
          lib.mapAttrs' (_: vlan: lib.nameValuePair (subInterface vlan) { useDHCP = false; }) taggedVlans
          # DHCP should run on the bridges, not on the uplink/slaves.
          // (
            if bondEnabled then
              lib.genAttrs cfg.bond.members (_: {
                useDHCP = lib.mkForce false;
              })
            else
              { ${cfg.uplink}.useDHCP = lib.mkForce false; }
          )
          // lib.genAttrs cfg.dhcpBridges (_: {
            useDHCP = true;
          })
          // {
            ${mgmtBridge} = {
              useDHCP = true;
            }
            // lib.optionalAttrs (cfg.mgmtMac != null) { macAddress = cfg.mgmtMac; };
          };
      };

      # Use MAC-based DHCP client ID on the management bridge so the
      # reservation matches the physical NIC.
      systemd.network.networks."30-${mgmtBridge}" = {
        matchConfig.Name = mgmtBridge;
        networkConfig.DHCP = "yes";
        dhcpV4Config = {
          ClientIdentifier = "mac";
        }
        // lib.optionalAttrs cfg.routeMetrics { RouteMetric = 100; };
      }
      // lib.optionalAttrs cfg.routeMetrics {
        routes = [
          {
            Destination = "0.0.0.0/0";
            Gateway = mgmtGateway;
            Metric = 100;
          }
        ]
        ++ map (network: {
          Destination = network;
          Gateway = mgmtGateway;
        }) cfg.mgmtRoutedNetworks;
      };
    }

    (mkIf bondEnabled {
      networking.bonds.${cfg.uplink} = {
        interfaces = cfg.bond.members;
        driverOptions = {
          inherit (cfg.bond) mode miimon;
        }
        // lib.optionalAttrs (cfg.bond.primary != null) { inherit (cfg.bond) primary; };
      };
    })

    (mkIf (bondEnabled && cfg.pinBridgeMac) {
      systemd.network.netdevs."40-${cfg.uplink}".netdevConfig = {
        Name = cfg.uplink;
        Kind = "bond";
        MACAddress = cfg.mgmtMac;
      };
    })

    (mkIf cfg.pinBridgeMac {
      systemd.network.netdevs."40-${mgmtBridge}".netdevConfig = {
        Name = mgmtBridge;
        Kind = "bridge";
        MACAddress = cfg.mgmtMac;
      };
    })

    (mkIf cfg.routeMetrics {
      # Keep server/storage VLAN addresses, but avoid competing default routes.
      systemd.network.networks = {
        "20-${serverBridge}" = {
          matchConfig.Name = serverBridge;
          networkConfig.DHCP = "yes";
          dhcpV4Config.RouteMetric = 200;
        };
        "40-${storageBridge}" = {
          matchConfig.Name = storageBridge;
          networkConfig.DHCP = "yes";
          dhcpV4Config.RouteMetric = 300;
        };
      };
    })
  ]);
}
