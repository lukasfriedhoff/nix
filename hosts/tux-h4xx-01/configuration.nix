{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/hardware/tuxedo/infinitybook-pro-16-gen8.nix
    ../../modules/nixos/profiles/desktop/gaming.nix
  ];

  networking.hostName = "tux-h4xx-01";

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = [ "ntfs" ];

  desktop.gaming = {
    enable = true;
    defaultRenderer = "intel";
  };

  fileSystems."/mnt/windows" = {
    device = "/dev/disk/by-uuid/5C3801A538017F70";
    fsType = "ntfs3";
    options = [
      "rw"
      "uid=1000"
      "gid=100"
      "umask=0022"
      "windows_names"
      "nofail"
      "x-gvfs-show"
    ];
  };

  services.pipewire.extraConfig = {
    pipewire = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 1024;
        "default.clock.min-quantum" = 512;
        "default.clock.max-quantum" = 2048;
      };
    };
    "pipewire-pulse" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 1024;
      };
      "stream.properties" = {
        "node.latency" = "1024/48000";
        "resample.quality" = 8;
      };
    };
  };

  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    defaultNetwork.settings = {
      dns_enabled = true;
    };
  };
}
