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
  # Region capture that opens in swappy for annotation (arrows, crop, text);
  # swappy's own copy/save buttons take over from there.
  screenshotAnnotate = pkgs.writeShellScript "screenshot-annotate" ''
    set -eu
    mkdir -p "${screenshotDir}"
    f="${screenshotDir}/$(date +%Y%m%d-%H%M%S).png"
    geom="$(${lib.getExe pkgs.slurp})" || exit 0
    ${lib.getExe pkgs.grim} -g "$geom" "$f"
    exec ${lib.getExe pkgs.swappy} -f "$f"
  '';
  # Quake-style dropdown: first press launches, later presses toggle the
  # scratchpad copy. The matching window rule floats/centers it.
  dropdownToggle = pkgs.writeShellScript "dropdown-terminal" ''
    if ! ${pkgs.sway}/bin/swaymsg '[app_id="dropdown-terminal"] scratchpad show'; then
      ${lib.getExe pkgs.alacritty} --class dropdown-terminal &
    fi
  '';
  clipboardPick = pkgs.writeShellScript "clipboard-pick" ''
    set -eu
    sel="$(${lib.getExe pkgs.cliphist} list | ${lib.getExe pkgs.wofi} --dmenu --prompt clipboard)" || exit 0
    printf '%s' "$sel" | ${lib.getExe pkgs.cliphist} decode | ${pkgs.wl-clipboard}/bin/wl-copy
  '';
  # Renames workspaces to "N: app app" so the waybar workspace list shows
  # what runs where; number-based switching keeps working because the
  # bindings use "workspace number N". Text labels instead of glyph icons
  # to match the bar's plain-text style (and no icon-font dependency).
  autonamePython = pkgs.python3.withPackages (ps: [ ps.i3ipc ]);
  autonameScript = pkgs.writeText "workspace-autoname.py" ''
    import i3ipc

    LABELS = {
        "alacritty": "term",
        "dropdown-terminal": "term",
        "foot": "term",
        "firefox": "web",
        "chromium-browser": "web",
        "code": "code",
        "code-url-handler": "code",
        "org.gnome.nautilus": "files",
        "thunderbird": "mail",
        "signal": "chat",
        "org.telegram.desktop": "chat",
        "discord": "chat",
        "spotify": "music",
        "mpv": "video",
        "steam": "game",
        "virt-manager": "vm",
    }


    def label(win):
        app = (win.app_id or win.window_class or "").lower()
        if not app:
            return None
        return LABELS.get(app, app.split(".")[-1][:10])


    def refresh(conn, _event=None):
        for ws in conn.get_tree().workspaces():
            if ws.num < 0:  # scratchpad
                continue
            seen = []
            for win in ws.leaves():
                tag = label(win)
                if tag and tag not in seen:
                    seen.append(tag)
            new = "%d: %s" % (ws.num, " ".join(seen)) if seen else "%d" % ws.num
            if ws.name != new:
                conn.command(
                    'rename workspace "%s" to "%s"'
                    % (ws.name.replace('"', ""), new.replace('"', ""))
                )


    conn = i3ipc.Connection()
    for ev in ("window::new", "window::close", "window::move"):
        conn.on(ev, refresh)
    refresh(conn)
    conn.main()
  '';
  # Bind helpers to the sway session so none of this leaks into a parallel
  # GNOME login (kanshi would fight mutter's display config, gammastep
  # would double GNOME's night light).
  swaySessionService = description: execStart: {
    Unit = {
      Description = description;
      PartOf = [ "sway-session.target" ];
      After = [ "sway-session.target" ];
    };
    Service = {
      ExecStart = execStart;
      Restart = "on-failure";
    };
    Install.WantedBy = [ "sway-session.target" ];
  };
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
            # MOD+Print additionally opens the capture in swappy to annotate.
            "Print" = "exec ${screenshotFull}";
            "Shift+Print" = "exec ${screenshotRegion}";
            "${mod}+Print" = "exec ${screenshotAnnotate}";
            # Quake-style dropdown terminal and clipboard history picker.
            "${mod}+grave" = "exec ${dropdownToggle}";
            "${mod}+p" = "exec ${clipboardPick}";
            # Media and brightness keys (no modifier, work when locked too
            # via the locked variants sway provides by default for XF86).
            # swayosd-client changes the value AND draws the on-screen bar;
            # --max-volume 140 matches the old wpctl -l 1.4 headroom.
            "XF86AudioRaiseVolume" =
              "exec ${pkgs.swayosd}/bin/swayosd-client --max-volume 140 --output-volume raise";
            "XF86AudioLowerVolume" = "exec ${pkgs.swayosd}/bin/swayosd-client --output-volume lower";
            "XF86AudioMute" = "exec ${pkgs.swayosd}/bin/swayosd-client --output-volume mute-toggle";
            "XF86AudioMicMute" = "exec ${pkgs.swayosd}/bin/swayosd-client --input-volume mute-toggle";
            "XF86MonBrightnessUp" = "exec ${pkgs.swayosd}/bin/swayosd-client --brightness raise";
            "XF86MonBrightnessDown" = "exec ${pkgs.swayosd}/bin/swayosd-client --brightness lower";
            "XF86AudioPlay" = "exec ${lib.getExe pkgs.playerctl} play-pause";
            "XF86AudioNext" = "exec ${lib.getExe pkgs.playerctl} next";
            "XF86AudioPrev" = "exec ${lib.getExe pkgs.playerctl} previous";
          }
        );
        window = {
          titlebar = false;
          border = 2;
          commands = [
            {
              criteria.app_id = "dropdown-terminal";
              command = "floating enable, resize set 60 ppt 60 ppt, move position center, move to scratchpad, scratchpad show";
            }
          ];
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
      # graphical-session.target is also reached by a GNOME login; bind to
      # the sway target so GNOME sessions stay waybar-free.
      systemd.target = "sway-session.target";
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

    # Output profiles switch on hotplug (dock/undock); hosts define the
    # actual profiles via services.kanshi.settings next to their hardware.
    services.kanshi = {
      enable = true;
      systemdTarget = "sway-session.target";
    };

    # Clipboard history (text and images); MOD+p opens the wofi picker.
    services.cliphist = {
      enable = true;
      systemdTargets = [ "sway-session.target" ];
    };

    # OSD daemon behind the volume/brightness keybindings. Idle outside
    # Sway: under GNOME nothing calls swayosd-client, so no target gating
    # is needed (the HM module offers none).
    services.swayosd.enable = true;

    # AeroSpace tiles automatically; autotiling brings Sway closest to that
    # by alternating split direction to follow the focused window's shape.
    systemd.user.services.autotiling = swaySessionService "autotiling" "${lib.getExe pkgs.autotiling}";

    # Night light for the Sway session (GNOME keeps its own). Central
    # European coordinates; precision is irrelevant for color temperature.
    systemd.user.services.gammastep = swaySessionService "gammastep" "${lib.getExe pkgs.gammastep} -l 50.1:8.7 -t 6500:4200";

    systemd.user.services.workspace-autoname = swaySessionService "workspace autoname" "${autonamePython}/bin/python ${autonameScript}";

    home.packages = [
      pkgs.playerctl
      pkgs.wofi
      pkgs.wl-clipboard
      pkgs.grim
      pkgs.slurp
      pkgs.swappy
      pkgs.brightnessctl
    ];
  };
}
