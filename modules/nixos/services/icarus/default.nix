{
  config,
  pkgs,
  lib,
  utils,
  ...
}:
let
  cfg = config.lukasf.icarus;
  # Set to {id}-{branch}-{password} for betas.
  steamApp = "2089300";
  serverBin = "/var/lib/steam-app-${steamApp}/icarus_server.x86_64";
in
{
  imports = [
    ./steam.nix
  ];

  options.lukasf.icarus = {
    enable = lib.mkEnableOption "Icarus dedicated server";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Open the Icarus server port in the firewall.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 2456;
      description = "Server port used by the Icarus dedicated server.";
    };

    serverName = lib.mkOption {
      type = lib.types.str;
      default = "h4xxarus";
      description = "In-game server name.";
    };

    serverPassword = lib.mkOption {
      type = lib.types.str;
      default = "Modeco80Icarus";
      description = "Password required to join the server.";
    };

    worldName = lib.mkOption {
      type = lib.types.str;
      default = "Dedicated";
      description = "World name passed to the Icarus server.";
    };

    saveDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/icarus/save";
      description = "Directory where Icarus stores saves.";
    };

    public = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Advertise the server publicly (enabled = 1, disabled = 0).";
    };

    backups = lib.mkOption {
      type = lib.types.int;
      default = 0;
      description = "Number of built-in rotation backups to keep.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Extra arguments passed to the Icarus server process.";
    };
  };

  config = lib.mkMerge [
    {
      lukasf.icarus.steam.enable = lib.mkDefault cfg.enable;
    }
    (lib.mkIf cfg.enable {
      users.users.icarus = {
        isSystemUser = true;
        # icarus puts save data in the home directory.
        home = "/var/lib/icarus";
        createHome = true;
        homeMode = "750";
        group = "icarus";
      };

      users.groups.icarus = { };

      networking.firewall = lib.mkIf cfg.openFirewall {
        allowedTCPPorts = [ cfg.port ];
        allowedUDPPorts = [ cfg.port ];
      };

      systemd.services.icarus = {
        wantedBy = [ "multi-user.target" ];

        # Install the game before launching.
        wants = [ "steam@${steamApp}.service" ];
        after = [ "steam@${steamApp}.service" ];

        serviceConfig = {
          ExecStart = utils.escapeSystemdExecArgs (
            [
              serverBin
              "-nographics"
              "-batchmode"
              # "-crossplay" # This is broken because it looks for "party" shared library in the wrong path.
              "-savedir"
              cfg.saveDir
              "-name"
              cfg.serverName
              "-port"
              (toString cfg.port)
              "-world"
              cfg.worldName
              "-password"
              cfg.serverPassword
              "-public"
              (if cfg.public then "1" else "0")
              "-backups"
              (toString cfg.backups)
            ]
            ++ cfg.extraArgs
          );
          Nice = "-5";
          PrivateTmp = true;
          Restart = "always";
          User = "icarus";
          WorkingDirectory = "~";
        };
        environment = {
          # linux64 directory is required by icarus.
          LD_LIBRARY_PATH = "/var/lib/steam-app-${steamApp}/linux64:${pkgs.glibc}/lib";
          SteamAppId = steamApp;
        };
      };
    })
  ];
}
