{ config, lib, pkgs, ... }:

{
  # Firmware & device support
  hardware.enableAllFirmware = true;
  services.fwupd.enable = true;
  services.power-profiles-daemon.enable = true;
  services.thermald.enable = true;
  services.hardware.bolt.enable = true;

  hardware.sensor.iio.enable = true;
  hardware.bluetooth.enable = true;

  programs.light.enable = true;

  # Graphics: Intel iGPU + NVIDIA RTX 4070 Max-Q (01:00.0)
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [ intel-media-driver vaapiIntel vaapiVdpau libvdpau-va-gl ];
  };

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.latest;
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  services.xserver.videoDrivers = [ "nvidia" "modesetting" ];

  environment.variables = {
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    __NV_PRIME_RENDER_OFFLOAD = "1";
    __VK_LAYER_NV_optimus = "NVIDIA_only";
  };

  boot.blacklistedKernelModules = [ "nouveau" ];

  environment.systemPackages = with pkgs; [
    nvtopPackages.full
    powertop
  ];

  services.udev.extraRules =
    let
      chmodBin = lib.getExe' pkgs.coreutils "chmod";
    in
    ''
      # Allow access to thunderbolt controller for logged-in users.
      ACTION=="add", SUBSYSTEM=="thunderbolt", RUN+="${chmodBin} 0660 /sys/%p/device"
    '';
}
