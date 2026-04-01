{
  config,
  lib,
  ...
}:

let
  cfg = config.hardwareProfiles.lenovo.thinkpadP15Gen2i;
in
{
  options.hardwareProfiles.lenovo.thinkpadP15Gen2i = {
    enable = lib.mkEnableOption "Lenovo ThinkPad P15 Gen2i hardware profile";
  };

  config = lib.mkIf cfg.enable {
    hardware.enableAllFirmware = true;
    hardware.bluetooth.enable = true;
    hardware.sensor.iio.enable = true;
    hardware.cpu.intel.updateMicrocode = lib.mkDefault true;

    services.fwupd.enable = true;
    services.hardware.bolt.enable = true;

    hardware.nvidia = {
      modesetting.enable = true;
      # Required for reliable Wayland resume with NVIDIA (installs nvidia-suspend/resume hooks).
      powerManagement.enable = true;
      powerManagement.finegrained = false;
      # Work around intermittent external display blanking/Xid crashes on Wayland.
      gsp.enable = false;
      open = false;
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      prime = {
        offload.enable = true;
        sync.enable = false;
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };

    services.xserver.videoDrivers = [
      "nvidia"
      "modesetting"
    ];

    # ThinkPad P15 Gen2i touchpad tuning override currently disabled.
    # boot.kernelParams = lib.mkAfter [ "psmouse.synaptics_intertouch=1" ];

    boot.blacklistedKernelModules = [ "nouveau" ];
  };
}
