{
  inputs,
  lib,
  pkgs,
  ...
}:

let
  hostName = "srv3";
  homelabDisks = import ../../../resources/homelab/disks.nix;
  cephTopology = import ../../../resources/homelab/ceph.nix;
  cephHost = cephTopology.hosts.${hostName};
  cephCluster = cephTopology.clusters.${cephHost.cluster};
  cephRoles = cephHost.roles;
  hasRole = role: lib.elem role cephRoles;
  cephDiskEntries = lib.filterAttrs (_: v: v.host == hostName && v.purpose == "ceph") homelabDisks;
  cephDisks = map (diskId: "/dev/disk/by-id/${diskId}") (lib.attrNames cephDiskEntries);
  cephLockboxKeys =
    lib.mapAttrsToList
      (diskId: disk: {
        device = "/dev/disk/by-id/${diskId}";
        secretKeyFile = disk.lockboxKeyFile;
      })
      (
        lib.filterAttrs (_: v: v.host == hostName && v.purpose == "ceph" && v ? lockboxKeyFile) homelabDisks
      );
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
  shared.network.domain = "lab.h4xx.io";

  homelab.personalServer = {
    enable = true;
    # Keep bootstrap SSH key from initrd-authorized.pub; avoid blocking install on this secret.
    managementPubKey = null;
    usePasswordAuth = false;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200n8"
    "console=ttyS1,115200n8"
  ];

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  boot.initrd.network.udhcpc.enable = true;
  boot.initrd.network.udhcpc.extraArgs = [
    "-t"
    "10"
    "-x"
    # DHCP option 61 (client identifier): 01 + mgmt MAC (52:54:00:0a:dd:ea)
    "0x3d:015254000addea"
    "-x"
    "hostname:srv3"
  ];

  lukasf.ceph = {
    enable = true;
    monHosts = cephCluster.monHosts or [ cephCluster.monIp ];
    monPort = cephCluster.monPort or 3300;
    bootstrap = {
      enable = hasRole "bootstrap";
      inherit (cephCluster) fsid;
      inherit (cephCluster) monIp;
      inherit (cephCluster) publicNetwork;
      inherit (cephCluster.bootstrap) singleHostDefaults;
      inherit (cephCluster.bootstrap) skipDashboard;
      inherit (cephCluster.bootstrap) extraArgs;
    };
    pools = lib.optionals (hasRole "bootstrap") cephCluster.pools;
    cephfs = lib.optionals (hasRole "bootstrap") (cephCluster.cephfs or [ ]);
    rgw = lib.mkIf (hasRole "bootstrap") (cephCluster.rgw or { });
    backup = lib.mkIf (hasRole "bootstrap") {
      enable = cephCluster.backup.enable or false;
      secretKeyFile = cephCluster.backup.secretKeyFile or null;
      retentionDays = cephCluster.backup.retentionDays or 30;
      schedule = cephCluster.backup.schedule or "daily";
    };
    osd = {
      devices = cephDisks;
      lockboxKeys = cephLockboxKeys;
      provisioner = "ceph-volume";
      encrypted = true;
      autoProvision = hasRole "osd";
      zapDevices = false;
    };
    monUpdate = {
      enable = hasRole "bootstrap";
      name = hostName;
      address = cephCluster.monIp;
    };
    healthCheck = {
      enable = true;
      checkLibvirt = hasRole "kvm";
      libvirtPools = [
        "testing-ceph-images"
        "testing-ceph-vmdisks"
      ];
    };
  };

  lukasf.ceph.client = lib.mkIf (hasRole "kvm") {
    enable = true;
    fsid = cephCluster.fsid or null;
    publicNetwork = cephCluster.publicNetwork or null;
  };

  lukasf.kvm = lib.mkIf (hasRole "kvm") {
    enable = true;
    storage = {
      backend = "ceph";
      ceph.pools = cephCluster.kvmPools;
    };
  };

  # Ensure QEMU has Ceph/RBD support for libvirt pools when KVM role is enabled.
  virtualisation.libvirtd.qemu.package = lib.mkIf (hasRole "kvm") (
    lib.mkForce (pkgs.qemu_kvm.override { cephSupport = true; })
  );

  homelab.kubernetes = {
    enable = true;
    extraK3sFlags = [
      "--tls-san srv3.lab.h4xx.io"
      "--tls-san srv3"
      "--tls-san ${cephCluster.monIp}"
    ];
    gitops = {
      enable = true;
      repoURL = "https://github.com/lukasfriedhoff/flux-cluster.git";
      branch = "develop";
      path = "./overlays/homelab";
      sourceName = "flux-cluster-testing";
      kustomizationName = "testing";
    };
  };

  # Needed by cephadm to satisfy asyncssh dependency for health checks.
  environment.systemPackages = with pkgs; [
    python3Packages.asyncssh
  ];

  networking.firewall.allowedTCPPorts = [ 4243 ];

  networking.extraHosts = ''
    # srv3 srv3.lab.h4xx.io
  '';
}
