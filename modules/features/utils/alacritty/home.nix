{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.alacritty;
in
{
  config = lib.mkMerge [
    {
      programs.alacritty.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      programs.alacritty.settings = {
        env.TERM = "xterm-256color";
        font = {
          size = lib.mkDefault 12;
          # draw_bold_text_with_bright_colors = true;
        };
        scrolling.multiplier = 5;
        selection.save_to_clipboard = true;
      };
    })
  ];
}
