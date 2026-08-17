{
  config,
  secrets,
  inputs,
  lib,
  ...
}:

let
  hostName = "srv8";
  clusterDomain = "lab.h4xx.io";
  prodApiHost = "srv2.lab.h4xx.io";
  mgmtMac = "1c:83:41:33:1b:37";
  k3sTokenSecret = "${secrets.primary}/k3s-server-token.txt";
  hasK3sToken = builtins.pathExists k3sTokenSecret;
in
{
  imports = [
    inputs.disko.nixosModules.disko
    ../../common/default.nix
    ../common.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = hostName;
  shared.network.domain = clusterDomain;

  homelab.vlanBridges = {
    enable = true;
    uplink = "bond0";
    inherit mgmtMac;
    bond = {
      members = [
        "enp4s0"
        "eno1"
      ];
      primary = "enp4s0";
    };
  };

  networking.extraHosts = ''
    10.1.30.26 srv2 srv2.lab.h4xx.io
    10.1.30.27 srv8 srv8.lab.h4xx.io
  '';

  homelab.personalServer = {
    enable = true;
    managementPubKey = null;
    usePasswordAuth = false;
  };

  users.users.root.openssh.authorizedKeys.keyFiles = [ ./initrd-authorized.pub ];
  users.users.nixos.openssh.authorizedKeys.keyFiles = [ ./initrd-authorized.pub ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  boot.initrd.network.udhcpc.enable = true;
  # Pin udhcpc to enp4s0 (igc, mgmt MAC 1c:83:41:33:1b:37). The wrapper script
  # in nixpkgs initrd-network.nix runs `udhcpc -i $iface … ${udhcpcArgs}` and
  # iterates over every NIC found in /sys/class/net; a trailing `-i enp4s0`
  # overrides the loop variable so DHCP always goes out the cabled port instead
  # of eno1 (r8169) which currently has no carrier.
  boot.initrd.network.udhcpc.extraArgs = [
    "-i"
    "enp4s0"
    "-t"
    "20"
    "-T"
    "3"
    "-x"
    "0x3d:011c8341331b37"
    "-x"
    "hostname:srv8"
  ];
  boot.initrd.availableKernelModules = lib.mkAfter [
    "igc"
    "r8169"
    "r8152"
  ];
  # Force-load the Intel 2.5G driver early so enp4s0 is in /sys/class/net by
  # the time the DHCP loop runs (availableKernelModules waits for a udev
  # device-trigger match, which has been racing the network setup).
  boot.initrd.kernelModules = [ "igc" ];

  # Only cryptroot is unlocked in initrd. Disko registers every LUKS content
  # type in boot.initrd.luks.devices unconditionally, which makes stage 1
  # prompt for three longhorn passphrases before the root prompt. Those are
  # unlocked in stage 2 by srv8-longhorn-disks.service.
  boot.initrd.luks.devices = lib.mkForce {
    cryptroot = {
      device = "/dev/disk/by-partlabel/disk-main-root";
      allowDiscards = true;
    };
  };

  homelab.longhornDisks = {
    enable = true;
    sopsFile = "${secrets.profileShared}/luks/srv8-longhorn.txt";
  };

  homelab.kubernetes = lib.mkIf hasK3sToken {
    enable = true;
    longhorn.enable = true;
    role = "agent";
    serverAddr = "https://${prodApiHost}:6443";
    tokenFile = config.sops.secrets."k3s-server-token".path;
    nodeIP = "10.1.30.27";
    nodeLabels = [
      "h4xx.io/gpu.present=true"
      "h4xx.io/gpu.vendor=amd"
      "h4xx.io/gpu.vaapi=true"
    ];
    extraFlags = [ "--kubelet-arg=max-pods=250" ];
  };

  sops.secrets."k3s-server-token" = lib.mkIf hasK3sToken {
    sopsFile = k3sTokenSecret;
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  users.groups.sudo = { };
  sops.secrets."login-password-hash" = {
    sopsFile = "${secrets.profileShared}/login-password-hash.txt";
    format = "binary";
    neededForUsers = true;
  };

  users.users.lukasf = {
    isNormalUser = true;
    group = "users";
    extraGroups = [
      "sudo"
      "wheel"
    ];
    hashedPasswordFile = config.sops.secrets."login-password-hash".path;
  };
  users.users.root = {
    initialHashedPassword = lib.mkForce null;
    hashedPasswordFile = config.sops.secrets."login-password-hash".path;
  };
}
