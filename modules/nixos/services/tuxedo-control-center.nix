{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.tuxedoControlCenter;
in
{
  options.lukasf.tuxedoControlCenter = {
    enable = lib.mkEnableOption "TUXEDO Control Center daemon and GUI";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../pkgs/tuxedo-control-center { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../../pkgs/tuxedo-control-center { }";
      description = "TUXEDO Control Center package to install and run.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    services.dbus.packages = [ cfg.package ];
    services.udev.packages = [ cfg.package ];
    security.polkit.enable = true;

    systemd.tmpfiles.rules = [
      "d /opt 0755 root root -"
      "L+ /opt/tuxedo-control-center - - - - ${cfg.package}/opt/tuxedo-control-center"
    ];

    systemd.services.tccd = {
      description = "TUXEDO Control Center Service";
      wantedBy = [ "multi-user.target" ];
      after = [ "dbus.service" ];
      path = [
        config.hardware.nvidia.package
        pkgs.coreutils
        pkgs.gawk
        pkgs.procps
        pkgs.which
        pkgs.gnugrep
        pkgs.gnused
      ];

      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${pkgs.coreutils}/bin/rm -f /var/run/tccd.pid";
        ExecStart = "${cfg.package}/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/service/tccd --start";
        ExecStop = "${cfg.package}/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/service/tccd --stop";
      };
    };

    systemd.services.tccd-sleep = {
      description = "TUXEDO Control Center Service (sleep/resume)";
      before = [ "sleep.target" ];
      wantedBy = [ "sleep.target" ];
      unitConfig.StopWhenUnneeded = true;

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/systemctl stop tccd";
        ExecStop = "${pkgs.systemd}/bin/systemctl start tccd";
      };
    };
  };
}
