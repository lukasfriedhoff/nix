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
  };

  # Sway session next to GNOME (GDM offers both); bindings mirror AeroSpace.
  desktop.sway = {
    enable = true;
    nvidiaUnsupportedGpu = true;
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
    mumble
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

  # Sway output layout via kanshi (switches on hotplug): external screen
  # above, internal panel centered below; positions use logical (scaled)
  # sizes. Profiles are matched first-to-last, so the EDID-specific
  # ultrawide entry must precede the generic HDMI fallback (LG 4K), which
  # would otherwise also match the ultrawide.
  home-manager.users.lukasf = {
    # Games belong on the external screen: sway spawns windows on the
    # focused output, and a game that fullscreens on the internal panel
    # locks in 2560x1600 and only gets scaled when moved. Proton's Wayland
    # driver exposes app_ids like "icarus-win64-shipping.exe"; XWayland
    # games use class "steam_app_<appid>".
    wayland.windowManager.sway.config.window.commands = [
      {
        criteria.app_id = "\\.exe$";
        command = "move window to output HDMI-A-1";
      }
      {
        criteria.class = "^steam_app_";
        command = "move window to output HDMI-A-1";
      }
    ];
    services.kanshi.settings = [
      {
        profile.name = "mobile";
        profile.outputs = [
          {
            criteria = "eDP-1";
            position = "0,0";
          }
        ];
      }
      {
        # 49" 5120x1440: scale 1 matches 27"-QHD density;
        # (5120-2560)/2 = 1280 x-offset.
        profile.name = "docked-ultrawide";
        profile.outputs = [
          {
            criteria = "LG Electronics LG ULTRAWIDE 304NTFA5P539";
            position = "0,0";
            scale = 1.0;
          }
          {
            criteria = "eDP-1";
            position = "1280,1440";
          }
        ];
      }
      {
        # LG 4K: (3840-2560)/2 = 640 x-offset. EDID-matched like the
        # ultrawide: a generic HDMI-A-1 criteria races against slow EDID
        # reads at session start and can capture the wrong monitor.
        profile.name = "docked-4k";
        profile.outputs = [
          {
            criteria = "LG Electronics LG HDR 4K 0x000684D2";
            position = "0,0";
          }
          {
            criteria = "eDP-1";
            position = "640,2160";
          }
        ];
      }
    ];
  };
}
