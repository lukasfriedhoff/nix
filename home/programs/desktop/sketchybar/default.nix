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
  sketchybarrc = ''
    # Upstream default demo config (with AeroSpace workspace clicks)
    PLUGIN_DIR="$CONFIG_DIR/plugins"

    sketchybar --bar position=top height=40 blur_radius=30 color=0x40000000

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

    SPACE_ICONS=("1" "2" "3" "4" "5" "6" "7" "8" "9" "10")
    for i in "''${!SPACE_ICONS[@]}"
    do
      sid="$(($i+1))"
      space=(
        space="$sid"
        icon="''${SPACE_ICONS[i]}"
        icon.padding_left=7
        icon.padding_right=7
        background.color=0x40ffffff
        background.corner_radius=5
        background.height=25
        label.drawing=off
        script="$PLUGIN_DIR/space.sh"
        click_script="aerospace workspace $sid"
      )
      sketchybar --add space space."$sid" left --set space."$sid" "''${space[@]}"
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
      sketchybar --set "$NAME" icon="$ICON" label="${PERCENTAGE}%"
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
      sketchybar --set "$NAME" background.drawing="$SELECTED"
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
