{
  config,
  lib,
  pkgs,
  ...
}:

# Daily git backup of the second-brain Obsidian vault to Forgejo
# (https://git.h4xx.io/lukasf/second-brain). LiveSync handles live
# multi-device sync; this timer owns history + the offsite-of-CouchDB copy.
# The vault repo carries the actual backup logic in scripts/backup.sh, so
# the unit stays inert (ConditionPathExists) on hosts without the vault.
let
  cfg = config.lukasf.secondBrainBackup;
in
{
  options.lukasf.secondBrainBackup = {
    enable = lib.mkEnableOption "daily git backup of the second-brain Obsidian vault to Forgejo";

    vaultPath = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/git/lukasfriedhoff/second-brain";
      description = "Checkout of the second-brain vault repo.";
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "systemd OnCalendar expression for the backup timer.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !pkgs.stdenv.isDarwin;
        message = "lukasf.secondBrainBackup uses a systemd user timer and is Linux-only.";
      }
    ];

    systemd.user.services.second-brain-backup = {
      Unit = {
        Description = "Back up second-brain vault to Forgejo";
        ConditionPathExists = "${cfg.vaultPath}/scripts/backup.sh";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${cfg.vaultPath}/scripts/backup.sh";
        # The repo's credential helper shells out to `nix run nixpkgs#sops`;
        # keep the system profile on PATH so it uses the host's nix.
        Environment = [
          "PATH=${
            lib.makeBinPath [
              pkgs.bash
              pkgs.coreutils
              pkgs.git
            ]
          }:/run/current-system/sw/bin"
        ];
      };
    };

    systemd.user.timers.second-brain-backup = {
      Unit.Description = "Daily second-brain vault backup";
      Timer = {
        OnCalendar = cfg.onCalendar;
        RandomizedDelaySec = "15m";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
