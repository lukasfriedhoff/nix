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

  # NSEventModifierFlags bits
  modifierBits = {
    shift = 131072;
    ctrl = 262144;
    alt = 524288;
    cmd = 1048576;
  };
  modifierMask = lib.foldl' (acc: m: acc + modifierBits.${m}) 0 (lib.unique cfg.modifiers);

  appBinary = "${cfg.package}/Applications/Easy Move+Resize.app/Contents/MacOS/Easy Move+Resize";
in
{
  options.programs.easyMoveResize = {
    enable = lib.mkEnableOption "Easy Move+Resize (modifier + mouse drag window move/resize)";

    package = lib.mkPackageOption pkgs "easy-move-resize" { };

    modifiers = lib.mkOption {
      type = lib.types.listOf (lib.types.enum (lib.attrNames modifierBits));
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
      };
    };

    home.activation.easyMoveResizePrefs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      /usr/bin/defaults write org.dmarcotte.Easy-Move-Resize ModifierFlags -int ${toString modifierMask}
    '';
  };
}
