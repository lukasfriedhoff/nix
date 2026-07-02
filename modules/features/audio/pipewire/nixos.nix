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
      wireplumber.extraConfig."10-bluetooth-audio" = {
        "monitor.bluez.properties" = {
          "bluez5.roles" = [
            "a2dp_sink"
            "a2dp_source"
            "bap_sink"
            "bap_source"
            "hsp_hs"
            "hsp_ag"
            "hfp_hf"
            "hfp_ag"
          ];
          "bluez5.codecs" = [
            "sbc"
            "sbc_xq"
            "aac"
          ];
          "bluez5.enable-sbc-xq" = true;
          "bluez5.hfphsp-backend" = "native";
        };
        "device.profile.priority.rules" = [
          {
            matches = [
              {
                "device.name" = "~bluez_card.*";
              }
            ];
            actions.update-props.priorities = [
              "a2dp-sink-sbc_xq"
              "a2dp-sink-aac"
              "a2dp-sink-sbc"
              "headset-head-unit"
              "headset-head-unit-cvsd"
            ];
          }
        ];
      };
      extraConfig."pipewire-pulse"."10-disable-stream-restore" = {
        "pulse.properties" = {
          "pulse.cmd.stream-restore" = false;
        };
      };
    };
  };
}
