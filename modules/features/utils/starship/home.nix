{ config, lib, ... }:

let
  cfg = config.programs.starship;
in
{
  config = lib.mkMerge [
    {
      programs.starship.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      programs.starship.settings = {
        add_newline = false;
        aws.disabled = true;
        gcloud.disabled = true;
        line_break.disabled = true;
      };
    })
  ];
}
