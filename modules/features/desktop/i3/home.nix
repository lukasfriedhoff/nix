# Home Manager side of the i3 session: renders the shared tiling
# definition (modules/features/desktop/tiling/def.nix) exactly like the
# Sway module does, so the streamed cloud desktop answers to the same
# muscle memory as the physical machines. X11 substitutes: rofi for wofi,
# dunst for mako, i3bar for waybar; Wayland-only tooling (grim, cliphist,
# swayosd, kanshi) is deliberately absent.
{
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  enabled = (osConfig.desktop.i3.enable or false) && !pkgs.stdenv.isDarwin;
  tiling = import ../tiling/def.nix { inherit lib; };
  mod = "Mod4";
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
  # i3 resolves Shift+<symbol> against the base keysym itself, so unlike
  # Sway no --to-code escape hatch is needed.
  renderBindings =
    defs:
    lib.filterAttrs (_: cmd: cmd != null) (
      lib.mapAttrs' (key: cmds: lib.nameValuePair (renderKey key) cmds.sway) defs
    );
  # Quake-style dropdown, i3 flavor of the Sway binding.
  dropdownToggle = pkgs.writeShellScript "dropdown-terminal" ''
    if ! ${pkgs.i3}/bin/i3-msg '[instance="dropdown-terminal"] scratchpad show'; then
      ${lib.getExe pkgs.alacritty} --class dropdown-terminal &
    fi
  '';
in
{
  config = lib.mkIf enabled {
    xsession.windowManager.i3 = {
      enable = true;
      config = {
        modifier = mod;
        terminal = "${lib.getExe pkgs.alacritty}";
        menu = "${lib.getExe pkgs.rofi} -show drun";
        # Merged over i3's stock bindings, same policy as the Sway module.
        keybindings = lib.mkOptionDefault (
          renderBindings tiling.mainBindings
          // {
            "${mod}+grave" = "exec ${dropdownToggle}";
          }
        );
        window = {
          titlebar = false;
          border = 2;
          commands = [
            {
              criteria.instance = "dropdown-terminal";
              command = "floating enable, resize set 1200 700, move position center, move scratchpad, scratchpad show";
            }
          ];
        };
        floating.titlebar = false;
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
      };
    };

    services.dunst.enable = true;
    home.packages = [ pkgs.rofi ];
  };
}
