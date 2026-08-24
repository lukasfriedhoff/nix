# Home Manager side of the Sway session. Renders the shared tiling
# definition (modules/features/desktop/tiling/def.nix) into Sway config,
# mirroring the AeroSpace bindings on macOS with Super instead of alt.
# Stylix themes sway, waybar, swaylock, wofi and foot on its own.
{
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  enabled = (osConfig.desktop.sway.enable or false) && !pkgs.stdenv.isDarwin;
  tiling = import ../tiling/def.nix { inherit lib; };
  mod = if (osConfig.desktop.sway.modifier or "super") == "alt" then "Mod1" else "Mod4";
  renderKey = tiling.renderKey {
    prefix = mod;
    sep = "+";
    shift = "Shift";
    keyNames = {
      "esc" = "Escape";
      "tab" = "Tab";
      "return" = "Return";
    };
  };
  # def key -> sway command, dropping entries without a Sway equivalent
  renderBindings =
    defs:
    lib.filterAttrs (_: cmd: cmd != null) (
      lib.mapAttrs' (key: cmds: lib.nameValuePair (renderKey key) cmds.sway) defs
    );
in
{
  config = lib.mkIf enabled {
    wayland.windowManager.sway = {
      enable = true;
      config = {
        modifier = mod;
        terminal = "foot";
        menu = "wofi --show drun";
        # Merged over Sway's stock bindings (mkOptionDefault), so anything
        # the shared definition does not cover keeps its upstream default.
        keybindings = lib.mkOptionDefault (
          renderBindings tiling.mainBindings
          // {
            # Screenshots (Linux-only; macOS ships its own): full screen on
            # Print, region on Shift+Print — saved under ~/Pictures and on
            # the clipboard.
            "Print" =
              "exec mkdir -p ~/Pictures/screenshots && ${lib.getExe pkgs.grim} ~/Pictures/screenshots/$(date +%Y%m%d-%H%M%S).png && ${lib.getExe pkgs.grim} - | ${pkgs.wl-clipboard}/bin/wl-copy";
            "Shift+Print" =
              "exec mkdir -p ~/Pictures/screenshots && ${lib.getExe pkgs.slurp} | ${lib.getExe pkgs.grim} -g - ~/Pictures/screenshots/$(date +%Y%m%d-%H%M%S).png && ${lib.getExe pkgs.slurp} | ${lib.getExe pkgs.grim} -g - - | ${pkgs.wl-clipboard}/bin/wl-copy";
          }
        );
        modes = {
          service = lib.filterAttrs (_: cmd: cmd != null) (
            lib.mapAttrs' (
              key: cmds: lib.nameValuePair (if key == "esc" then "Escape" else renderKey key) cmds.sway
            ) tiling.serviceBindings
          );
        };
        gaps = {
          inner = 10;
          smartGaps = true;
        };
        bars = [ ]; # waybar below instead of swaybar
        startup = [ { command = "${lib.getExe pkgs.waybar}"; } ];
        # Workspace->output pinning intentionally omitted: output names are
        # per-host; add workspaceOutputAssign in the host config once the
        # monitor names are known (swaymsg -t get_outputs).
      };
    };

    programs.waybar.enable = true;
    programs.swaylock.enable = true;
    services.swayidle = {
      enable = true;
      events = [
        {
          event = "before-sleep";
          command = "${lib.getExe pkgs.swaylock} -f";
        }
      ];
      timeouts = [
        {
          timeout = 300;
          command = "${lib.getExe pkgs.swaylock} -f";
        }
        {
          timeout = 600;
          command = "${pkgs.sway}/bin/swaymsg 'output * power off'";
          resumeCommand = "${pkgs.sway}/bin/swaymsg 'output * power on'";
        }
      ];
    };

    home.packages = [
      pkgs.foot
      pkgs.wofi
      pkgs.wl-clipboard
      pkgs.grim
      pkgs.slurp
      pkgs.brightnessctl
    ];
  };
}
