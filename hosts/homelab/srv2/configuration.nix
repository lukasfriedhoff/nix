{
  config,
  secrets,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  hostName = "srv2";
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

  homelab.vlanBridges = {
    enable = true;
    uplink = "enp1s0";
    mgmtMac = "68:1d:ef:39:95:b2";
  };

  homelab.personalServer = {
    enable = true;
    managementPubKey = null;
    usePasswordAuth = false;
  };

  sops.secrets."flux-cluster-token" = {
    sopsFile = "${secrets.primary}/flux-cluster-bootstrap-token.txt";
    owner = "root";
    format = "binary";
    mode = "0400";
  };

  sops.secrets."flux-sops-age-key" = {
    sopsFile = "${secrets.primary}/flux-sops-age.key";
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  homelab.longhornDisks = {
    enable = true;
    sopsFile = "${secrets.profileShared}/luks/srv2-mdraid.txt";
  };

  fileSystems."/var/lib/longhorn-disk2" = {
    device = "/dev/disk/by-uuid/9e956847-70aa-45b2-bcfa-ce7282bb0965";
    fsType = "ext4";
    options = [
      "defaults"
      "nofail"
      "x-systemd.device-timeout=30s"
    ];
  };

  fileSystems."/var/lib/longhorn-disk3" = {
    device = "/dev/disk/by-uuid/8736b05a-badf-423a-b5fb-29ae8ff4d215";
    fsType = "ext4";
    options = [
      "defaults"
      "nofail"
      "x-systemd.device-timeout=30s"
    ];
  };

  homelab.kubernetes = {
    enable = true;
    longhorn.enable = true;
    embeddedRegistry = true;
    # Embedded etcd instead of the single-server sqlite default; k3s migrates
    # the existing datastore in place on the first restart with this flag.
    # Required before srv8/srv9 can join as control planes
    # (docs/deployment/k3s-ha-migration.md).
    clusterInit = true;
    tlsSans = [
      "srv2.lab.h4xx.io"
      "srv2"
      "10.1.30.26"
    ];
    nodeIP = "10.1.30.26";
    nodeLabels = [
      "h4xx.io/gpu.present=true"
      "h4xx.io/gpu.vendor=intel"
      "h4xx.io/gpu.vaapi=true"
    ];
    extraFlags = [ "--kubelet-arg=max-pods=250" ];
    gitops = {
      enable = true;
      repoURL = "https://github.com/lukasfriedhoff/flux-cluster.git";
      branch = "main";
      path = "./overlays/homelab";
      tokenFile = config.sops.secrets."flux-cluster-token".path;
      sopsAgeKeyFile = config.sops.secrets."flux-sops-age-key".path;
      username = "lukasfriedhoff";
      sourceName = "flux-cluster";
      kustomizationName = "homelab";
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  # r8169 hang mitigation: the 2026-08-24 outage was this NIC stopping with
  # "NETDEV WATCHDOG: transmit queue 0 timed out" and never recovering
  # (kernel bugzilla 107421, RH bugs 1733837/1692075). ASPM, EEE and large
  # offloads are the documented triggers. pcie_aspm applies at next reboot.
  boot.kernelParams = [ "pcie_aspm=off" ];
  systemd.services.r8169-nic-quirks = {
    description = "Disable EEE and offloads on the Realtek NIC";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-subsystem-net-devices-enp1s0.device" ];
    bindsTo = [ "sys-subsystem-net-devices-enp1s0.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.ethtool}/bin/ethtool --set-eee enp1s0 eee off || true
      ${pkgs.ethtool}/bin/ethtool -K enp1s0 tso off gso off gro off || true
    '';
  };

  boot.initrd.network.udhcpc.enable = true;
  boot.initrd.network.udhcpc.extraArgs = [
    # Some switches delay forwarding briefly after link-up (STP/listen state).
    # Retry longer so initrd SSH unlock remains available during boot.
    "-t"
    "20"
    "-T"
    "3"
    "-x"
    # DHCP option 61 (client identifier): 01 + MAC (no separators)
    "0x3d:01681def3995b2"
    "-x"
    "hostname:srv2"
  ];

  boot.initrd.availableKernelModules = lib.mkAfter [
    "e1000e"
    "igb"
    "igc"
    "ixgbe"
    "r8169"
    "r8152"
  ];

  # Only cryptroot is unlocked in initrd. Disko registers every LUKS content
  # type in boot.initrd.luks.devices unconditionally, which makes stage 1
  # stall waiting for the longhorn data partitions. Those are unlocked in
  # stage 2 by srv2-longhorn-disks.service.
  boot.initrd.luks.devices = lib.mkForce {
    cryptroot = {
      device = "/dev/disk/by-partlabel/disk-main-root";
      allowDiscards = true;
    };
  };

  networking.extraHosts = ''
    # srv2 srv2.lab.h4xx.io 10.42.1.91
  '';

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
