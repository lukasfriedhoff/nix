{
  config,
  lib,
  pkgs,
  ...
}:

# X11/sway-style window dragging for macOS: hold the modifier and drag with
# the left button to move, right button to resize - anywhere in the window.
# Uses the local pkgs/easy-move-resize package (not in nixpkgs). The app
# needs Accessibility permission on first launch (System Settings ->
# Privacy & Security -> Accessibility).
let
  cfg = config.programs.easyMoveResize;

  # The app stores ModifierFlags as a comma-joined string of key names
  # (EMRPreferences.m), NOT as a bitmask.
  modifierNames = {
    shift = "SHIFT";
    ctrl = "CTRL";
    alt = "ALT";
    cmd = "CMD";
    fn = "FN";
  };
  modifierString = lib.concatMapStringsSep "," (m: modifierNames.${m}) (lib.unique cfg.modifiers);

  appBinary = "${cfg.package}/Applications/Easy Move+Resize.app/Contents/MacOS/Easy Move+Resize";
in
{
  options.programs.easyMoveResize = {
    enable = lib.mkEnableOption "Easy Move+Resize (modifier + mouse drag window move/resize)";

    package = lib.mkPackageOption pkgs "easy-move-resize" { };

    modifiers = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames modifierNames));
      default = [ "alt" ];
      description = ''
        Modifier keys that must be held for mouse move/resize. All listed
        keys must be held together (upstream default is cmd+ctrl).
      '';
      example = [
        "cmd"
        "ctrl"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "programs.easyMoveResize is only available on macOS.";
      }
      {
        assertion = cfg.modifiers != [ ];
        message = "programs.easyMoveResize.modifiers must not be empty (a bare mouse drag would grab every window).";
      }
    ];

    home.packages = [ cfg.package ];

    launchd.agents.easy-move-resize = {
      enable = true;
      config = {
        ProgramArguments = [ appBinary ];
        KeepAlive = true;
        RunAtLoad = true;
        # Without this the agent spawns as daemon-class and App Nap throttles
        # it; its event tap then services clicks with multi-second latency,
        # macOS times the tap out, and drags fall through to the app below.
        ProcessType = "Interactive";
      };
    };

    home.activation.easyMoveResizePrefs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      /usr/bin/defaults write org.dmarcotte.Easy-Move-Resize ModifierFlags -string "${modifierString}"
    '';
  };
}
