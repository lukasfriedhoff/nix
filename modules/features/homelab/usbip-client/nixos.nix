{
  config,
  lib,
  pkgs,
  ...
}:

# Attach a remote USB device exported via usbip (kernel USB-over-IP).
# Used for the Thread RCP stick (ZBT-1) exported by srv4 while it is not
# physically attached to this host. The service self-discovers the busid
# by vendor:product match and re-attaches whenever the link drops (server
# reboot, replug), so no per-port configuration is needed.
let
  cfg = config.homelab.usbipClient;
  usbipPkg = config.boot.kernelPackages.usbip;
in
{
  options.homelab.usbipClient = {
    enable = lib.mkEnableOption "attach a remote usbip-exported USB device";

    server = lib.mkOption {
      type = lib.types.str;
      example = "srv4.lab.h4xx.io";
      description = "Host running usbipd with the device bound.";
    };

    usbId = lib.mkOption {
      type = lib.types.str;
      default = "10c4:ea60";
      description = "vendor:product of the device to attach (default: CP210x / ZBT-1).";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = [ "vhci-hcd" ];
    environment.systemPackages = [ usbipPkg ];

    systemd.services.usbip-attach = {
      description = "Attach ${cfg.usbId} from ${cfg.server} via usbip";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        usbipPkg
        pkgs.gnugrep
        pkgs.gawk
        pkgs.coreutils
      ];
      # Watchdog loop: (re)attach whenever no vhci port is in use. usbip has
      # no attached-device query by id, so port state is the liveness signal.
      script = ''
        while true; do
          if ! usbip port 2>/dev/null | grep -q "Port in Use"; then
            busid=$(usbip list -r ${cfg.server} 2>/dev/null \
              | grep -B0 "${cfg.usbId}" | awk '/^ *[0-9]+-[0-9.]+:/ {gsub(":","",$1); print $1; exit}')
            if [ -n "$busid" ]; then
              echo "attaching $busid from ${cfg.server}"
              usbip attach -r ${cfg.server} -b "$busid" || true
            else
              echo "device ${cfg.usbId} not exported by ${cfg.server} (yet)"
            fi
          fi
          sleep 30
        done
      '';
      serviceConfig = {
        Restart = "always";
        RestartSec = 10;
      };
    };
  };
}
