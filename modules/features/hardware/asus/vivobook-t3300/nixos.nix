{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardwareProfiles.asus.vivobookT3300;
  disableEmmcQueue = pkgs.writeShellScript "disable-emmc-cq" ''
    set -euo pipefail
    for dev in /sys/block/mmcblk*/queue/use_cq; do
      [ -e "$dev" ] || continue
      echo 0 > "$dev" || true
    done
  '';
in
{
  options.hardwareProfiles.asus.vivobookT3300 = {
    enable = lib.mkEnableOption "ASUS VivoBook T3300 hardware profile";
  };

  config = lib.mkIf cfg.enable {
    hardware.enableAllFirmware = true;
    hardware.bluetooth.enable = true;
    hardware.sensor.iio.enable = true;
    hardware.cpu.intel.updateMicrocode = lib.mkDefault true;

    services = {
      fwupd.enable = true;
      thermald.enable = true;
      power-profiles-daemon.enable = true;
      hardware.bolt.enable = true;
    };

    services.libinput.enable = true;

    # Touchscreen optimisations
    environment.systemPackages = with pkgs; [
      libwacom
      powertop
    ];

    # ASUS eMMC command queue tends to lock up under load; disable blk-mq
    boot.kernelParams = [
      "mmc_core.queue_depth=2"
      "mmc_core.default_cmdq_depth=0"
    ];

    systemd.services.disable-emmc-cq = {
      description = "Disable blk-mq command queueing on eMMC devices";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = disableEmmcQueue;
      };
    };

    systemd.tmpfiles.rules = [
      "w /sys/module/mmc_core/parameters/default_cmdq_depth - - - - 0"
    ];

    # Tablet-friendly defaults
    services.udev.extraRules = ''
      # Enable orientation sensor permissions for regular users
      SUBSYSTEM=="iio", GROUP="input", MODE="0660"
    '';
  };
}
