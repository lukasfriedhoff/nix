# Single source of truth for tiling window management across platforms.
# Consumed by desktop/aerospace/home.nix (macOS) and desktop/sway/home.nix
# (Linux) so both render the same logical bindings: same keys, matching
# semantics, one place to tune. AeroSpace uses alt as modifier, Sway uses
# Super (Mod4) — alt collides with application shortcuts on Linux.
#
# Key names use AeroSpace spelling ("slash", "comma", "minus", "equal",
# "semicolon", digits, letters); consumers translate for their backend.
# A null command means "no equivalent on this backend" — e.g. Sway has
# explicit splitv/splith, AeroSpace deliberately has none (its answer to
# nested splits is join-with, bound in service mode).
{ lib }:
rec {
  workspaces = map toString (lib.range 1 9);

  # Workspace -> monitor pinning; AeroSpace consumes this directly.
  # Sway's per-host output names differ per machine, so the Sway module
  # leaves output assignment to the host until names are collected.
  mainMonitorWorkspaces = [
    "1"
    "2"
    "3"
    "4"
    "5"
  ];
  secondaryMonitorWorkspaces = [
    "6"
    "7"
    "8"
    "9"
  ];

  mainBindings =
    let
      both = c: {
        aerospace = c;
        sway = c;
      };
    in
    {
      # Layout
      "slash" = {
        aerospace = "layout tiles horizontal vertical";
        sway = "layout toggle split";
      };
      "comma" = {
        aerospace = "layout accordion horizontal vertical";
        sway = "layout toggle tabbed stacking";
      };

      # Explicit splits (Sway only; AeroSpace covers this via join-with)
      "v" = {
        aerospace = null;
        sway = "splitv";
      };
      "b" = {
        aerospace = null;
        sway = "splith";
      };

      # Focus (vim-style)
      "h" = both "focus left";
      "j" = both "focus down";
      "k" = both "focus up";
      "l" = both "focus right";

      # Move windows
      "shift-h" = both "move left";
      "shift-j" = both "move down";
      "shift-k" = both "move up";
      "shift-l" = both "move right";

      # Resize
      "shift-minus" = {
        aerospace = "resize smart -50";
        sway = "resize shrink width 50 px or 5 ppt";
      };
      "shift-equal" = {
        aerospace = "resize smart +50";
        sway = "resize grow width 50 px or 5 ppt";
      };

      # Fullscreen and floating
      "f" = {
        aerospace = "fullscreen";
        sway = "fullscreen toggle";
      };
      "shift-f" = {
        aerospace = "layout floating tiling";
        sway = "floating toggle";
      };

      # Quick toggle between the two most recent workspaces
      "tab" = {
        aerospace = "workspace-back-and-forth";
        sway = "workspace back_and_forth";
      };

      # Linux-only session helpers (macOS handles these natively)
      "return" = {
        aerospace = null;
        sway = "exec foot";
      };
      "d" = {
        aerospace = null;
        sway = "exec wofi --show drun";
      };
      "shift-q" = {
        aerospace = null;
        sway = "kill";
      };

      # Service mode entry
      "shift-semicolon" = both "mode service";
    }
    // lib.listToAttrs (
      map (ws: {
        name = ws;
        value = {
          aerospace = "workspace ${ws}";
          sway = "workspace number ${ws}";
        };
      }) workspaces
    )
    // lib.listToAttrs (
      map (ws: {
        name = "shift-${ws}";
        value = {
          aerospace = "move-node-to-workspace ${ws}";
          sway = "move container to workspace number ${ws}";
        };
      }) workspaces
    );

  # Service mode: reload plus tree surgery. join-with is how AeroSpace
  # builds nested splits (e.g. one window left, two stacked right: focus
  # the middle window, enter service mode, join-with right); Sway does the
  # same with splitv/splith in main mode, so it only needs reload here.
  serviceBindings = {
    "esc" = {
      aerospace = [
        "reload-config"
        "mode main"
      ];
      sway = "reload; mode default";
    };
    "r" = {
      aerospace = [
        "flatten-workspace-tree"
        "mode main"
      ];
      sway = null;
    };
    "shift-h" = {
      aerospace = [
        "join-with left"
        "mode main"
      ];
      sway = null;
    };
    "shift-j" = {
      aerospace = [
        "join-with down"
        "mode main"
      ];
      sway = null;
    };
    "shift-k" = {
      aerospace = [
        "join-with up"
        "mode main"
      ];
      sway = null;
    };
    "shift-l" = {
      aerospace = [
        "join-with right"
        "mode main"
      ];
      sway = null;
    };
  };

  # Render a def key ("shift-h", "slash", "3") into a backend key string.
  renderKey =
    {
      prefix, # e.g. "alt" or "Mod4"
      sep, # "-" for aerospace, "+" for sway
      shift, # "shift" or "Shift"
      keyNames ? { }, # per-backend special key spellings
    }:
    key:
    let
      hasShift = lib.hasPrefix "shift-" key;
      bare = lib.removePrefix "shift-" key;
      spelled = keyNames.${bare} or bare;
      parts = [ prefix ] ++ lib.optional hasShift shift ++ [ spelled ];
    in
    lib.concatStringsSep sep parts;
}
