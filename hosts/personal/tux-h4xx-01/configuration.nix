{
  lib,
  pkgs,
  ...
}:

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

  boot.initrd.luks.devices.cryptdata = {
    device = "/dev/disk/by-uuid/f23e2488-c72e-402a-9bf7-7a2348861b87";
    allowDiscards = true;
  };

  fileSystems."/data" = {
    device = "/dev/tux-data/data";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.device-timeout=10s"
    ];
  };

  fileSystems."/home/lukasf/Nextcloud" = {
    device = lib.mkForce "/data/nextcloud";
    fsType = lib.mkForce "none";
    options = lib.mkForce [
      "bind"
      "x-systemd.requires-mounts-for=/data"
    ];
  };

  fileSystems."/home/lukasf/nextcloud-prod" = {
    device = "/data/nextcloud-prod";
    fsType = "none";
    options = [
      "bind"
      "x-systemd.requires-mounts-for=/data"
    ];
  };

  fileSystems."/home/lukasf/nextcloud-testing" = {
    device = "/data/nextcloud-testing";
    fsType = "none";
    options = [
      "bind"
      "x-systemd.requires-mounts-for=/data"
    ];
  };

  fileSystems."/home/lukasf/media" = {
    device = lib.mkForce "/data/media";
    fsType = lib.mkForce "none";
    options = lib.mkForce [
      "bind"
      "x-systemd.requires-mounts-for=/data"
    ];
  };

  systemd.tmpfiles.rules = [
    "d /data 0755 root root -"
    "d /data/media 0750 lukasf users -"
    "d /data/nextcloud 0750 lukasf users -"
    "d /data/nextcloud-prod 0750 lukasf users -"
    "d /data/nextcloud-testing 0750 lukasf users -"
  ];

  desktop.personalWorkstation = {
    enable = true;
    wireguardAddress = "10.1.90.2/24";
    cephClientName = "tux";
  };

  # Keep WireGuard system-managed so homelab DNS and remote builders are
  # available before rebuilds and other privileged automation.
  lukasf.wireguard.homelab.userUnit.enable = false;

  desktop.gaming = {
    defaultRenderer = "nvidia";
    fpsLimit = null;
  };

  lukasf.tuxedoControlCenter.enable = true;
  lukasf.shadowTech.enable = true;
  lukasf.kvm.enable = true;

  virtualisation = {
    docker.enable = true;
    podman.dockerCompat = lib.mkForce false;
  };

  environment.systemPackages = with pkgs; [
    k3d
  ];

  users.users.lukasf.extraGroups = lib.mkAfter [
    "docker"
    "gamemode"
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

  services.pipewire.extraConfig = {
    pipewire."10-stable-clock" = {
      "context.properties" = {
        "default.clock.rate" = 48000;
        "default.clock.quantum" = 2048;
        "default.clock.min-quantum" = 1024;
        "default.clock.max-quantum" = 2048;
      };
    };
    "pipewire-pulse"."20-stable-latency" = {
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
