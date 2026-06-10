{
  config,
  lib,
  ...
}:

let
  cfg = config.lukasf.pipewire;
in
{
  options.lukasf.pipewire = {
    enable = lib.mkEnableOption "PipeWire audio stack";

    support32Bit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable 32-bit ALSA support (useful for games and legacy apps).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = cfg.support32Bit;
      pulse.enable = true;
      extraConfig."pipewire-pulse"."10-disable-stream-restore" = {
        "pulse.properties" = {
          "pulse.cmd.stream-restore" = false;
        };
      };
    };
  };
}
