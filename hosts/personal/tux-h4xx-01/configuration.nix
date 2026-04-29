{ lib, ... }:

{
  imports = [
    ../../common/default.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "tux-h4xx-01";

  # Keep a system-owned age key copy so sops-nix can decrypt secrets reliably
  # during activation and make WireGuard key material available at boot/login.
  sops.age.keyFile = "/var/lib/sops-nix/age/keys.txt";

  system.activationScripts.bootstrapSopsAgeKey = {
    text = ''
      if [ ! -s /var/lib/sops-nix/age/keys.txt ] && [ -s /home/lukasf/.config/sops/age/keys.txt ]; then
        install -d -m 0700 /var/lib/sops-nix/age
        install -m 0600 /home/lukasf/.config/sops/age/keys.txt /var/lib/sops-nix/age/keys.txt
      fi
    '';
  };

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
  lukasf.shadowTech.enable = true;
  lukasf.kvm.enable = true;

  users.users.lukasf.extraGroups = lib.mkAfter [
    "input"
    "libvirtd"
    "kvm"
  ];
  boot.kernelModules = [ "uinput" ];
  services.udev.extraRules = ''
    KERNEL=="uinput", MODE="0660", GROUP="input"
  '';

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

}
