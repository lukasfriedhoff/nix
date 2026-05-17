{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.hardwareProfiles.tuxedo.infinitybookPro16Gen8;
in
{
  options.hardwareProfiles.tuxedo.infinitybookPro16Gen8 = {
    enable = lib.mkEnableOption "TUXEDO InfinityBook Pro 16 Gen8 hardware profile";
  };

  config = lib.mkIf cfg.enable {
    # Firmware & device support
    hardware.enableAllFirmware = true;
    services.fwupd.enable = true;
    services.power-profiles-daemon.enable = false; # Conflicts with tccd
    services.thermald.enable = true;
    services.hardware.bolt.enable = true;

    hardware.sensor.iio.enable = true;
    hardware.bluetooth.enable = true;

    hardware.tuxedo-rs = {
      enable = false; # Use tccd instead for full TDP/fan/cTGP control
      tailor-gui.enable = false;
    };

    hardware.acpilight.enable = true; # Brightness control (replaces deprecated programs.light)

    # Graphics: Intel iGPU + NVIDIA RTX 4070 Max-Q (01:00.0)
    hardware.graphics = {
      enable = true;
      extraPackages = with pkgs; [
        intel-media-driver
        intel-vaapi-driver
        libva-vdpau-driver
        libvdpau-va-gl
      ];
    };

    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = true;
      powerManagement.finegrained = false; # Incompatible with PRIME sync
      open = true; # Use open driver like Tuxedo OS
      dynamicBoost.enable = true; # Enable nvidia-powerd for CPU/GPU power balancing
      package = config.boot.kernelPackages.nvidiaPackages.stable;
      prime = {
        offload.enable = false;
        sync.enable = true; # Use dGPU for all rendering (better gaming perf)
        intelBusId = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };
    };

    # Lower swappiness for better gaming performance (Tuxedo OS uses 10)
    boot.kernel.sysctl."vm.swappiness" = 10;

    services.xserver.videoDrivers = [
      "nvidia"
      "modesetting"
    ];

    boot.blacklistedKernelModules = [ "nouveau" ];

    environment.systemPackages = with pkgs; [
      mesa-demos # provides glxinfo for quick renderer checks
      nvtopPackages.full
      powertop
    ];

    programs.gamemode.enable = true;

    services.udev.extraRules =
      let
        chmodBin = lib.getExe' pkgs.coreutils "chmod";
      in
      ''
        # Allow access to thunderbolt controller for logged-in users.
        ACTION=="add", SUBSYSTEM=="thunderbolt", RUN+="${chmodBin} 0660 /sys/%p/device"

        # Keep USB input devices awake to avoid losing keyboard/mouse on autosuspend.
        ACTION=="add", SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}=="*:030101:*", TEST=="power/control", ATTR{power/control}="on"
        ACTION=="add", SUBSYSTEM=="usb", ENV{ID_USB_INTERFACES}=="*:030102:*", TEST=="power/control", ATTR{power/control}="on"
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="046d", ATTR{idProduct}=="c539", TEST=="power/control", ATTR{power/control}="on"
        ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="0951", ATTR{idProduct}=="16be", TEST=="power/control", ATTR{power/control}="on"
      '';
  };
}
