# SketchyBar macOS status bar.
# Uses the built-in home-manager programs.sketchybar module.
# This file provides opinionated default config (Catppuccin Mocha + AeroSpace integration).
{
  lib,
  pkgs,
  ...
}:
{
  programs.sketchybar.config = lib.mkIf pkgs.stdenv.isDarwin (
    lib.mkDefault ''
      # --- Bar appearance (Catppuccin Mocha) ---
      sketchybar --bar \
        height=32 \
        blur_radius=30 \
        position=top \
        sticky=off \
        padding_left=10 \
        padding_right=10 \
        color=0xa01e1e2e

      # --- Default item properties ---
      sketchybar --default \
        icon.font="SF Pro:Semibold:14.0" \
        icon.color=0xffcdd6f4 \
        label.font="SF Pro:Semibold:14.0" \
        label.color=0xffcdd6f4 \
        background.color=0x40313244 \
        background.corner_radius=5 \
        background.height=24 \
        padding_left=5 \
        padding_right=5 \
        label.padding_left=4 \
        label.padding_right=10 \
        icon.padding_left=10 \
        icon.padding_right=4

      # --- Space indicators (AeroSpace integration) ---
      SPACE_ICONS=("1" "2" "3" "4" "5" "6" "7" "8" "9")
      for i in "''${!SPACE_ICONS[@]}"
      do
        sid="$(($i+1))"
        space=(
          space="$sid"
          icon="''${SPACE_ICONS[i]}"
          icon.padding_left=7
          icon.padding_right=7
          background.color=0x40313244
          background.corner_radius=5
          background.height=24
          label.drawing=off
          script="sketchybar --set \$NAME background.drawing=\$SELECTED"
          click_script="aerospace workspace $sid 2>/dev/null"
        )
        sketchybar --add space space."$sid" left \
                   --set space."$sid" "''${space[@]}"
      done

      # --- Front app (currently focused window) ---
      sketchybar --add item front_app left \
                 --set front_app \
                   icon.drawing=off \
                   script='sketchybar --set $NAME label="$INFO"' \
                 --subscribe front_app front_app_switched

      # --- Clock ---
      sketchybar --add item clock right \
                 --set clock \
                   update_freq=10 \
                   icon="" \
                   script='sketchybar --set $NAME label="$(date "+%H:%M")"'

      # --- Battery ---
      sketchybar --add item battery right \
                 --set battery \
                   update_freq=120 \
                   script='sketchybar --set $NAME label="$(pmset -g batt | grep -Eo "\d+%" | head -1)"'

      # --- CPU usage ---
      sketchybar --add item cpu right \
                 --set cpu \
                   update_freq=5 \
                   icon="" \
                   script='sketchybar --set $NAME label="$(top -l 1 | grep "CPU usage" | awk "{print \$3}")"'

      # Force initial update
      sketchybar --update
    ''
  );
}
