{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.evolution;
  defaultGpgKey = "7357275F6DFB9956E72B5BF9F52D0D35FC8BD0DF";
in
{
  options.programs.evolution = {
    enable = lib.mkEnableOption "Evolution groupware client";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.evolution;
      defaultText = lib.literalExpression "pkgs.evolution";
      description = "Evolution package to install.";
    };

    gpgKey = lib.mkOption {
      type = lib.types.str;
      default = defaultGpgKey;
      description = ''
        OpenPGP fingerprint used for signing outgoing e-mail. The default matches
        the personal key imported by <literal>modules/features/devops/sops-age</literal>.
      '';
      example = "7357275F6DFB9956E72B5BF9F52D0D35FC8BD0DF";
    };

    nextcloud = {
      enable = lib.mkEnableOption ''
        Install helpers required for Evolution ↔ Nextcloud integration (contacts,
        calendars, tasks) via GNOME Online Accounts and Evolution Data Server.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.gpgKey != "";
        message = "programs.evolution.gpgKey must be a non-empty OpenPGP fingerprint";
      }
    ];

    home.packages = [
      cfg.package
      pkgs.evolution-ews
      pkgs.seahorse
    ]
    ++ lib.optionals cfg.nextcloud.enable [
      pkgs.gnome-online-accounts
      pkgs.evolution-data-server
      pkgs.gnome-calendar
      pkgs.gnome-contacts
      pkgs.nextcloud-client
    ];

    # DConf tweaks ensure Evolution always proposes the right OpenPGP key.
    dconf.settings = {
      "org/gnome/evolution/mail" = {
        composer-sign = true;
        composer-encrypt = false;
        default-signing-key = cfg.gpgKey;
        default-encryption-key = cfg.gpgKey;
      };
    };
  };
}
