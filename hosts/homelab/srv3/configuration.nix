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
    managementPubKey = "ssh/srv3-personal-mgmt.pub";
    usePasswordAuth = false;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  swapDevices = lib.mkForce [
    {
      device = "/dev/disk/by-label/swap";
      label = "swap";
    }
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
      lockboxKeys = [ ];
      provisioner = "ceph-volume";
      encrypted = true;
      autoProvision = hasRole "osd";
      # One-time destructive wipe for reprovisioning; the Ceph module now guards
      # with a marker file so this does not repeat every boot.
      zapDevices = true;
    };
    monUpdate = {
      enable = hasRole "bootstrap";
      name = hostName;
      address = cephCluster.monIp;
    };
    healthCheck = {
      enable = true;
      checkLibvirt = hasRole "kvm";
      libvirtPools = map (p: p.name) cephCluster.kvmPools;
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

  networking.extraHosts = ''
    # srv3 srv3.lab.h4xx.io
  '';
}
