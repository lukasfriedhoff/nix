{
  config,
  lib,
  ...
}:

{
  hardware.enableAllFirmware = true;
  hardware.bluetooth.enable = true;
  hardware.sensor.iio.enable = true;
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;

  services.fwupd.enable = true;
  services.hardware.bolt.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
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

  boot.blacklistedKernelModules = [ "nouveau" ];
}
