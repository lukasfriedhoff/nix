{
  config,
  lib,
  linuxUser ? null,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.protonvpn;
  defaultUser = linuxUser;
in
{
  options.lukasf.protonvpn = {
    enable = lib.mkEnableOption "Proton VPN CLI/GUI integration (NetworkManager-based)";

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = defaultUser;
      defaultText = if linuxUser != null then lib.literalExpression "linuxUser" else "null";
      description = "Desktop user to run ProtonVPN user services for.";
    };

    cliPackage = lib.mkPackageOption pkgs "proton-vpn-cli" { };

    gui = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the Proton VPN GTK app.";
      };
      package = lib.mkPackageOption pkgs "proton-vpn" { };
      autostart = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Start the Proton VPN GTK app minimized in the tray for the configured user.";
      };
    };

    autoConnect = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Auto-connect ProtonVPN on boot using the CLI.";
      };
      country = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Country to use with `protonvpn connect --country` (two-letter code or full name).";
      };
      city = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "City to use with `protonvpn connect --city`.";
      };
      server = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Explicit server name (takes precedence over country/city).";
      };
    };
  };

  config = lib.mkIf cfg.enable (
    let
      autostartUser = cfg.user;
      connectArgs =
        if cfg.autoConnect.server != null then
          lib.escapeShellArg cfg.autoConnect.server
        else if cfg.autoConnect.country != null then
          "--country ${lib.escapeShellArg cfg.autoConnect.country}"
        else if cfg.autoConnect.city != null then
          "--city ${lib.escapeShellArg cfg.autoConnect.city}"
        else
          "";
    in
    {
      assertions = [
        {
          assertion = config.networking.networkmanager.enable;
          message = "lukasf.protonvpn requires networking.networkmanager.enable = true;";
        }
        {
          assertion = (!cfg.autoConnect.enable) || autostartUser != null;
          message = "lukasf.protonvpn.autoConnect requires a user (set lukasf.protonvpn.user or linuxUser).";
        }
      ];

      environment.systemPackages = [
        cfg.cliPackage
      ]
      ++ lib.optional cfg.gui.enable cfg.gui.package;

      networking.networkmanager.plugins = lib.mkAfter [ pkgs.networkmanager-openvpn ];

      systemd.user.services.protonvpn-gui-autostart =
        lib.mkIf (cfg.gui.enable && cfg.gui.autostart && autostartUser != null)
          {
            description = "Proton VPN GTK app (tray)";
            wantedBy = [ "graphical-session.target" ];
            partOf = [ "graphical-session.target" ];
            unitConfig = {
              ConditionUser = autostartUser;
            };
            serviceConfig = {
              ExecStart = "${cfg.gui.package}/bin/protonvpn-app --start-minimized";
              Restart = "on-failure";
            };
          };

      systemd.services.protonvpn-autoconnect = lib.mkIf cfg.autoConnect.enable {
        description = "ProtonVPN auto-connect";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          cfg.cliPackage
          pkgs.networkmanager
          pkgs.networkmanager-openvpn
          pkgs.wireguard-tools
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = autostartUser;
          ExecStart = "${cfg.cliPackage}/bin/protonvpn connect ${connectArgs}";
          ExecStop = "${cfg.cliPackage}/bin/protonvpn disconnect";
        };
      };
    }
  );
}
