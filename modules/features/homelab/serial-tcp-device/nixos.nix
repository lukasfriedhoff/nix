{
  config,
  lib,
  pkgs,
  ...
}:

# Bridge a remote serial device (served raw over TCP, e.g. by socat/ser2net
# or MikroTik `/port remote-access`) to a stable local pty. Used for the
# ZBT-1 Thread RCP: real UART parameters (baud, flow control) are applied
# by the serving end; the pty here is transparent. If the TCP link drops,
# socat exits and systemd restarts it with a fresh pty behind the same
# symlink; consumers holding the old pty see EOF and must reopen (the OTBR
# pod restarts and picks up the new one).
let
  cfg = config.homelab.serialTcpDevice;
in
{
  options.homelab.serialTcpDevice = {
    enable = lib.mkEnableOption "local pty bridged to a remote serial-over-TCP export";

    remote = lib.mkOption {
      type = lib.types.str;
      example = "srv4.lab.h4xx.io:3333";
      description = "host:port serving the raw serial stream.";
    };

    devicePath = lib.mkOption {
      type = lib.types.str;
      default = "/dev/ttyThreadRCP";
      description = "Stable symlink to the local pty.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.serial-tcp-device = {
      description = "pty ${cfg.devicePath} bridged to ${cfg.remote}";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        # wait-slave: create the pty immediately but connect TCP only once a
        # consumer opens the device - otherwise the idle pty master reports
        # HUP and socat exits before OTBR ever attaches.
        ExecStart = "${lib.getExe pkgs.socat} PTY,link=${cfg.devicePath},raw,echo=0,mode=0666,wait-slave TCP:${cfg.remote}";
        Restart = "always";
        RestartSec = 5;
      };
    };
  };
}
