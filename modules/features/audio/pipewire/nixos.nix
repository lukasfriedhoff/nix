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

    a2dpOnlyDevices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "20:18:5B:56:61:BA" ];
      description = ''
        Bluetooth MAC addresses restricted to A2DP audio. Stops WirePlumber
        from attempting HFP/HSP against speakers without a voice profile:
        the failed SDP probes keep the ACL link out of sniff mode, which
        starves other hosts on multipoint speakers and can wedge A2DP
        transport setup during connect.
      '';
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
        "monitor.bluez.rules" = map (address: {
          matches = [ { "device.address" = address; } ];
          actions.update-props = {
            "bluez5.auto-connect" = [ "a2dp_sink" ];
          };
        }) cfg.a2dpOnlyDevices;
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
