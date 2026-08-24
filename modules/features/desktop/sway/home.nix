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
  screenshotDir = "$HOME/Pictures/screenshots";
  screenshotFull = pkgs.writeShellScript "screenshot-full" ''
    set -eu
    mkdir -p "${screenshotDir}"
    f="${screenshotDir}/$(date +%Y%m%d-%H%M%S).png"
    ${lib.getExe pkgs.grim} "$f"
    ${pkgs.wl-clipboard}/bin/wl-copy < "$f"
  '';
  screenshotRegion = pkgs.writeShellScript "screenshot-region" ''
    set -eu
    mkdir -p "${screenshotDir}"
    f="${screenshotDir}/$(date +%Y%m%d-%H%M%S).png"
    geom="$(${lib.getExe pkgs.slurp})" || exit 0
    ${lib.getExe pkgs.grim} -g "$geom" "$f"
    ${pkgs.wl-clipboard}/bin/wl-copy < "$f"
  '';
  # --to-code binds by physical keycode, so shifted symbol keys work:
  # with plain keysym matching, Shift+semicolon arrives as "colon" and a
  # Mod4+Shift+semicolon binding never fires (same for minus/equal).
  renderBindings =
    defs:
    lib.filterAttrs (_: cmd: cmd != null) (
      lib.mapAttrs' (key: cmds: lib.nameValuePair "--to-code ${renderKey key}" cmds.sway) defs
    );
in
{
  config = lib.mkIf enabled {
    wayland.windowManager.sway = {
      enable = true;
      config = {
        modifier = mod;
        terminal = "${lib.getExe pkgs.alacritty}";
        menu = "wofi --show drun";
        # Merged over Sway's stock bindings (mkOptionDefault), so anything
        # the shared definition does not cover keeps its upstream default.
        keybindings = lib.mkOptionDefault (
          renderBindings tiling.mainBindings
          // {
            # Screenshots (Linux-only; macOS ships its own): capture once,
            # then copy the written file — never prompt or grab twice.
            "Print" = "exec ${screenshotFull}";
            "Shift+Print" = "exec ${screenshotRegion}";
            # Media and brightness keys (no modifier, work when locked too
            # via the locked variants sway provides by default for XF86)
            "XF86AudioRaiseVolume" =
              "exec ${pkgs.wireplumber}/bin/wpctl set-volume -l 1.4 @DEFAULT_AUDIO_SINK@ 5%+";
            "XF86AudioLowerVolume" = "exec ${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
            "XF86AudioMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
            "XF86AudioMicMute" = "exec ${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
            "XF86MonBrightnessUp" = "exec ${lib.getExe pkgs.brightnessctl} set +5%";
            "XF86MonBrightnessDown" = "exec ${lib.getExe pkgs.brightnessctl} set 5%-";
            "XF86AudioPlay" = "exec ${lib.getExe pkgs.playerctl} play-pause";
            "XF86AudioNext" = "exec ${lib.getExe pkgs.playerctl} next";
            "XF86AudioPrev" = "exec ${lib.getExe pkgs.playerctl} previous";
          }
        );
        window = {
          titlebar = false;
          border = 2;
        };
        floating.titlebar = false;
        modes = {
          service = lib.filterAttrs (_: cmd: cmd != null) (
            lib.mapAttrs' (
              key: cmds:
              lib.nameValuePair (if key == "esc" then "Escape" else "--to-code ${renderKey key}") cmds.sway
            ) tiling.serviceBindings
          );
        };
        gaps = {
          inner = 10;
          smartGaps = true;
        };
        bars = [ ]; # waybar runs as a user service bound to sway-session.target
        # Workspace->output pinning intentionally omitted: output names are
        # per-host; add workspaceOutputAssign in the host config once the
        # monitor names are known (swaymsg -t get_outputs).
      };
    };

    # GNOME starts a keyring for its session; Sway must bring its own or
    # apps like VS Code find no org.freedesktop.secrets provider.
    services.gnome-keyring.enable = true;

    # Desktop notifications (GNOME ships its own daemon; Sway needs one).
    services.mako = {
      enable = true;
      settings.default-timeout = 8000;
    };

    # Systemd-managed so it survives config reloads and comes back
    # restarted (not orphaned) after every Home Manager activation.
    programs.waybar = {
      enable = true;
      systemd.enable = true;
      settings.mainBar = {
        layer = "top";
        position = "top";
        height = 26;
        modules-left = [
          "sway/workspaces"
          "sway/mode"
        ];
        modules-center = [ "sway/window" ];
        modules-right = [
          "wireplumber"
          "network"
          "battery"
          "clock"
          "tray"
        ];
        wireplumber = {
          format = "vol {volume}%";
          format-muted = "muted";
        };
        network = {
          format-wifi = "{essid} {signalStrength}%";
          format-ethernet = "eth {ifname}";
          format-disconnected = "offline";
        };
        battery = {
          format = "bat {capacity}%";
          states.warning = 25;
          states.critical = 10;
        };
        clock.format = "{:%a %d.%m %H:%M}";
        tray.spacing = 8;
      };
    };
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
      pkgs.playerctl
      pkgs.wofi
      pkgs.wl-clipboard
      pkgs.grim
      pkgs.slurp
      pkgs.brightnessctl
    ];
  };
}
