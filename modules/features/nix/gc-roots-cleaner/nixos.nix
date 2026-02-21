{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.nix.gcRootsCleaner;
in
{
  options.nix.gcRootsCleaner = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Clean stale GC roots that point to /tmp.";
    };

    maxAgeDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 7;
      description = "Maximum age (days) for /tmp GC roots before deletion.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nix-gc-roots-cleaner = {
      description = "Clean stale Nix GC roots pointing to /tmp";
      serviceConfig.Type = "oneshot";
      script = ''
        echo "Cleaning GC roots under /tmp older than ${toString cfg.maxAgeDays} days..."
        ${pkgs.findutils}/bin/find /nix/var/nix/gcroots/auto \
          -type l \
          -mtime +${toString cfg.maxAgeDays} \
          -lname '/tmp/*' \
          -print \
          -delete
        echo "Done cleaning stale GC roots"
      '';
    };

    systemd.timers.nix-gc-roots-cleaner = {
      description = "Timer for cleaning stale Nix GC roots";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = config.nix.gc.dates;
        Persistent = true;
      };
    };

    systemd.services.nix-gc = lib.mkIf config.nix.gc.automatic {
      wants = [ "nix-gc-roots-cleaner.service" ];
      after = [ "nix-gc-roots-cleaner.service" ];
    };
  };
}
