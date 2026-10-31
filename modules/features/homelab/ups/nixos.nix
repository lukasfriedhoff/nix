{
  config,
  lib,
  pkgs,
  ...
}@args:

# Coordinated fleet shutdown on the APC UPS at Hiesfelder (NUT).
#
# One host owns the USB cable and runs the driver + upsd (role = "primary");
# every other server on the same UPS runs only upsmon against it (role =
# "secondary"). When mains fails and the UPS reports less runtime than
# `runtimeLowSeconds` (or less charge than `chargeLowPercent`), the primary's
# upsmon raises FSD: the secondaries power off at once, the primary waits
# `HOSTSYNC` seconds for them, powers off itself, and on its way down tells
# the UPS to cut the outlets (killpower). When mains returns the UPS re-powers
# the outlets and the hosts boot back to their initrd LUKS prompt.
#
# The low-battery decision is deliberately taken from NUT's own thresholds
# (`ignorelb` + `override.battery.*.low`), not from the UPS firmware's LB flag,
# which on APC Back-UPS models fires only at a few percent of charge.
let
  cfg = config.homelab.ups;
  secrets = args.secrets or null;

  nets = import ../../../../resources/homelab/networks.nix;
  mgmtBridge = "brvlan${toString nets.vlans.mgmt.id}";

  isPrimary = cfg.role == "primary";
  secretName = "nut-upsmon-password";
  passwordFile = config.sops.secrets.${secretName}.path;
  # upsd.users accounts: the primary's upsmon may raise FSD, the secondaries'
  # may only observe. Both share one password file; the secret is what gates
  # access to upsd at all, the role is what gates the shutdown right.
  monitorUser = if isPrimary then "upsmon-primary" else "upsmon-secondary";
in
{
  options.homelab.ups = {
    enable = lib.mkEnableOption "NUT-coordinated shutdown of this host on the shared APC UPS";

    role = lib.mkOption {
      type = lib.types.enum [
        "primary"
        "secondary"
      ];
      description = ''
        primary: this host has the UPS on USB and runs the driver, upsd and the
        deciding upsmon. secondary: this host only runs upsmon against the
        primary and powers off when the primary declares a forced shutdown.
      '';
    };

    upsName = lib.mkOption {
      type = lib.types.str;
      default = "apc";
      description = "NUT name of the UPS (ups.conf section / `upsc <name>`).";
    };

    primaryAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.3.30.31";
      description = ''
        Management-VLAN address the primary's upsd listens on and the
        secondaries connect to (srv9 by default).
      '';
    };

    driver = lib.mkOption {
      type = lib.types.str;
      default = "usbhid-ups";
      description = "NUT driver for the UPS (primary only).";
    };

    port = lib.mkOption {
      type = lib.types.str;
      default = "auto";
      description = "Driver port; `auto` lets usbhid-ups find the USB device (primary only).";
    };

    runtimeLowSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 600;
      description = ''
        Declare LOW BATTERY, and with it the fleet shutdown, once the UPS
        reports fewer seconds of estimated runtime than this while on battery.
      '';
    };

    chargeLowPercent = lib.mkOption {
      type = lib.types.ints.between 1 99;
      default = 20;
      description = ''
        Second guard for a UPS whose runtime estimate is unreliable: also
        declare LOW BATTERY under this charge percentage while on battery.
      '';
    };

    hostSyncSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60;
      description = ''
        How long the primary waits for the secondaries to disconnect after
        raising FSD before it powers itself off (upsmon HOSTSYNC).
      '';
    };

    sopsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = if secrets != null then "${secrets.profileShared}/nut/upsmon-password.txt" else null;
      defaultText = lib.literalExpression ''"''${secrets.profileShared}/nut/upsmon-password.txt"'';
      description = ''
        SOPS-encrypted file (binary format) holding the shared upsmon
        password. Decrypted by sops-nix and handed to upsd/upsmon as a
        systemd credential; identical on the primary and every secondary.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.sopsFile != null;
            message = "homelab.ups: set sopsFile (no `secrets` specialArg available to derive the default).";
          }
        ];

        sops.secrets.${secretName} = {
          inherit (cfg) sopsFile;
          format = "binary";
          mode = "0400";
          owner = "root";
        };

        power.ups = {
          enable = true;
          mode = if isPrimary then "netserver" else "netclient";

          upsmon = {
            monitor.${cfg.upsName} = {
              system = "${cfg.upsName}@${if isPrimary then "localhost" else cfg.primaryAddress}";
              powerValue = 1;
              user = monitorUser;
              inherit passwordFile;
              type = cfg.role;
            };
            settings = {
              MINSUPPLIES = 1;
              # Poll fast enough that a 10-minute runtime threshold is not
              # overshot by minutes of polling slack.
              POLLFREQ = 5;
              POLLFREQALERT = 5;
              # A primary that stays unreachable this long counts as dead for
              # the secondaries (they then do NOT shut down: no FSD, no action).
              DEADTIME = 60;
              HOSTSYNC = cfg.hostSyncSeconds;
              FINALDELAY = 5;
              SHUTDOWNCMD = "${pkgs.systemd}/bin/systemctl poweroff";
              NOTIFYFLAG = [
                [
                  "ONBATT"
                  "SYSLOG+WALL"
                ]
                [
                  "ONLINE"
                  "SYSLOG+WALL"
                ]
                [
                  "LOWBATT"
                  "SYSLOG+WALL"
                ]
                [
                  "FSD"
                  "SYSLOG+WALL"
                ]
                [
                  "SHUTDOWN"
                  "SYSLOG+WALL"
                ]
                [
                  "COMMBAD"
                  "SYSLOG"
                ]
                [
                  "COMMOK"
                  "SYSLOG"
                ]
                [
                  "NOCOMM"
                  "SYSLOG"
                ]
              ];
            };
          };
        };
      }

      (lib.mkIf isPrimary {
        power.ups = {
          ups.${cfg.upsName} = {
            inherit (cfg) driver port;
            description = "APC UPS at Hiesfelder (USB on this host)";
            directives = [
              # Decide LB from our thresholds, not the firmware's flag.
              "ignorelb"
              "override.battery.runtime.low = ${toString cfg.runtimeLowSeconds}"
              "override.battery.charge.low = ${toString cfg.chargeLowPercent}"
              "pollinterval = 5"
            ];
          };

          # Bind every address: the management IP is a DHCP lease that need not
          # be up when upsd starts, and a failed bind would leave the fleet
          # without its arbiter. Reachability is narrowed by the firewall below.
          upsd.listen = [ { address = "0.0.0.0"; } ];

          users = {
            upsmon-primary = {
              inherit passwordFile;
              upsmon = "primary";
            };
            upsmon-secondary = {
              inherit passwordFile;
              upsmon = "secondary";
            };
          };
        };

        # upsd for the secondaries, management VLAN only (the module's own
        # openFirewall would open 3493 on every interface).
        networking.firewall.interfaces.${mgmtBridge}.allowedTCPPorts = [ 3493 ];
      })
    ]
  );
}
