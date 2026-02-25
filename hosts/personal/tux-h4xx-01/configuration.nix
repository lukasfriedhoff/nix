{ lib, ... }:

{
  imports = [
    ../../common/default.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "tux-h4xx-01";

  hardwareProfiles.tuxedo.infinitybookPro16Gen8.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];
  boot.loader.systemd-boot.configurationLimit = lib.mkDefault 10;
  boot.loader.generic-extlinux-compatible.configurationLimit = lib.mkDefault 10;
  boot.loader.grub.configurationLimit = lib.mkDefault 10;

  desktop.personalWorkstation = {
    enable = true;
    wireguardAddress = "10.1.90.2/24";
    cephClientName = "tux";
  };

  lukasf.wireguard.homelab.userUnit.enable = true;

  desktop.gaming.defaultRenderer = "nvidia";

  lukasf.tuxedoControlCenter.enable = true;

  # Power management
  powerManagement.powertop.enable = false;
  services.tlp.enable = false;
  networking.networkmanager.wifi.powersave = true;

  services.pipewire.extraConfig = {
    pipewire = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 2048;
        "default.clock.min-quantum" = 1024;
        "default.clock.max-quantum" = 2048;
      };
    };
    "pipewire-pulse" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 2048;
      };
      "stream.properties" = {
        "node.latency" = "2048/48000";
        "resample.quality" = 8;
      };
    };
  };

  # Keep the Windows partition declared so the unit exists, but avoid
  # automounting or blocking boots/switches if the volume is dirty.
  # Define explicit units for the Windows partition so the unit files exist in
  # the generation that switch-to-configuration references.
  systemd.mounts = [
    {
      what = "/dev/disk/by-uuid/5C3801A538017F70";
      where = "/mnt/windows";
      type = "ntfs3";
      options = "noauto,nofail,x-systemd.device-timeout=1s";
      wantedBy = [ ];
    }
  ];

  systemd.automounts = [
    {
      where = "/mnt/windows";
      wantedBy = [ "multi-user.target" ];
      automountConfig.IdleTimeoutSec = "1min";
    }
  ];
}
