# SketchyBar macOS status bar.
# Home Manager module using the upstream default config (FelixKratz/SketchyBar)
# with workspace clicks mapped to AeroSpace.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.sketchybar;
  tiling = import ../tiling/def.nix { inherit lib; };
  workspaceList = lib.concatStringsSep " " tiling.workspaces;
  sketchybarrc = ''
    # Upstream default demo config (with AeroSpace workspace clicks)
    PLUGIN_DIR="$CONFIG_DIR/plugins"

    sketchybar --bar position=top height=40 blur_radius=30 color=0x40000000 display=all

    default=(
      padding_left=5
      padding_right=5
      icon.font="Hack Nerd Font:Bold:17.0"
      label.font="Hack Nerd Font:Bold:14.0"
      icon.color=0xffffffff
      label.color=0xffffffff
      icon.padding_left=4
      icon.padding_right=4
      label.padding_left=4
      label.padding_right=4
    )
    sketchybar --default "''${default[@]}"

    # AeroSpace workspaces are virtual (all inside one macOS space), so
    # plain items driven by the aerospace_workspace_change event replace the
    # native `space` items of the upstream demo config.
    sketchybar --add event aerospace_workspace_change

    for sid in ${workspaceList}
    do
      space=(
        icon="$sid"
        icon.padding_left=7
        icon.padding_right=7
        background.color=0x40ffffff
        background.corner_radius=5
        background.height=25
        background.drawing=off
        label.drawing=off
        script="$PLUGIN_DIR/space.sh"
        click_script="aerospace workspace $sid"
      )
      sketchybar --add item space."$sid" left \
                 --set space."$sid" "''${space[@]}" \
                 --subscribe space."$sid" aerospace_workspace_change
    done

    sketchybar --add item chevron left \
               --set chevron icon= label.drawing=off \
               --add item front_app left \
               --set front_app icon.drawing=off script="$PLUGIN_DIR/front_app.sh" \
               --subscribe front_app front_app_switched

    sketchybar --add item clock right \
               --set clock update_freq=10 icon=  script="$PLUGIN_DIR/clock.sh" \
               --add item volume right \
               --set volume script="$PLUGIN_DIR/volume.sh" \
               --subscribe volume volume_change \
               --add item battery right \
               --set battery update_freq=120 script="$PLUGIN_DIR/battery.sh" \
               --subscribe battery system_woke power_source_change

    sketchybar --update
    sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE="$(aerospace list-workspaces --focused)"
  '';

  plugins = {
    "battery.sh" = ''
      #!/bin/sh
      PERCENTAGE="$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)"
      CHARGING="$(pmset -g batt | grep 'AC Power')"
      [ -z "$PERCENTAGE" ] && exit 0
      case "$PERCENTAGE" in
        9[0-9]|100) ICON="" ;;
        [6-8][0-9]) ICON="" ;;
        [3-5][0-9]) ICON="" ;;
        [1-2][0-9]) ICON="" ;;
        *) ICON="" ;;
      esac
      [ -n "$CHARGING" ] && ICON=""
      sketchybar --set "$NAME" icon="$ICON" label="''${PERCENTAGE}%"
    '';

    "clock.sh" = ''
      #!/bin/sh
      sketchybar --set "$NAME" label="$(date '+%d/%m %H:%M')"
    '';

    "front_app.sh" = ''
      #!/bin/sh
      [ "$SENDER" = "front_app_switched" ] && sketchybar --set "$NAME" label="$INFO"
    '';

    "space.sh" = ''
      #!/bin/sh
      # Highlight the focused AeroSpace workspace; NAME is "space.<id>".
      if [ "$FOCUSED_WORKSPACE" = "''${NAME#space.}" ]; then
        sketchybar --set "$NAME" background.drawing=on
      else
        sketchybar --set "$NAME" background.drawing=off
      fi
    '';

    "volume.sh" = ''
      #!/bin/sh
      [ "$SENDER" != "volume_change" ] && exit 0
      VOLUME="$INFO"
      case "$VOLUME" in
        [6-9][0-9]|100) ICON="󰕾" ;;
        [3-5][0-9]) ICON="󰖀" ;;
        [1-9]|[1-2][0-9]) ICON="󰕿" ;;
        *) ICON="󰖁" ;;
      esac
      sketchybar --set "$NAME" icon="$ICON" label="$VOLUME%"
    '';
  };
in
{
  config = lib.mkMerge [
    {
      programs.sketchybar.enable = lib.mkDefault pkgs.stdenv.isDarwin;
    }
    (lib.mkIf (cfg.enable && pkgs.stdenv.isDarwin) {
      programs.sketchybar.config = lib.mkDefault sketchybarrc;

      # aerospace must be callable from the service (workspace clicks and
      # the initial focused-workspace query).
      programs.sketchybar.extraPackages = [ config.programs.aerospace.package ];

      # Install plugin scripts referenced by the config
      xdg.configFile = lib.mapAttrs' (
        name: text:
        lib.nameValuePair "sketchybar/plugins/${name}" {
          inherit text;
          executable = true;
        }
      ) plugins;
    })
  ];
}
