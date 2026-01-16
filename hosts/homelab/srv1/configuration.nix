{
  config,
  inputs,
  lib,
  pkgs,
  secrets,
  ...
}:

let
  hostName = "srv1";
  homelabDisks = import ../../../resources/homelab/disks.nix;
  nets = import ../../../resources/homelab/networks.nix;
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
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = hostName;
  networking.domain = "lab.h4xx.io";
  networking.useNetworkd = true;
  networking.networkmanager.enable = false;
  networking.defaultGateway = lib.mkForce null;
  networking.nameservers = [ "10.1.30.1" ];
  # DHCP should run on the bridge (brvlan30), not on the slave.
  networking.interfaces.eno1.useDHCP = lib.mkForce false;
  networking.vlans = {
    "eno1.20" = {
      id = nets.vlans.server.id;
      interface = "eno1";
    };
    "eno1.40" = {
      id = nets.vlans.storage.id;
      interface = "eno1";
    };
    "eno1.10" = {
      id = nets.vlans.lan.id;
      interface = "eno1";
    };
    "eno1.12" = {
      id = nets.vlans.iot.id;
      interface = "eno1";
    };
    "eno1.13" = {
      id = nets.vlans.windows.id;
      interface = "eno1";
    };
    "eno1.50" = {
      id = nets.vlans.lab.id;
      interface = "eno1";
    };
  };

  # Bring VLAN subinterfaces up even without an IP so bridges attach cleanly.
  networking.interfaces."eno1.20".useDHCP = false;
  networking.interfaces."eno1.40".useDHCP = false;
  networking.interfaces."eno1.10".useDHCP = false;
  networking.interfaces."eno1.12".useDHCP = false;
  networking.interfaces."eno1.13".useDHCP = false;
  networking.interfaces."eno1.50".useDHCP = false;

  # Libvirt-friendly bridges for each VLAN (mgmt on brvlan30).
  networking.bridges = {
    brvlan10.interfaces = [ "eno1.10" ];
    brvlan12.interfaces = [ "eno1.12" ];
    brvlan13.interfaces = [ "eno1.13" ];
    brvlan20.interfaces = [ "eno1.20" ];
    brvlan30.interfaces = [ "eno1" ]; # untagged mgmt
    brvlan40.interfaces = [ "eno1.40" ];
    brvlan50.interfaces = [ "eno1.50" ];
  };
  networking.interfaces.brvlan30 = {
    useDHCP = true;
  };
  networking.interfaces.brvlan20.useDHCP = true;
  networking.interfaces.brvlan40.useDHCP = true;
  networking.hosts = {
    "127.0.0.2" = lib.mkForce [ ];
  };

  # Use MAC-based DHCP client ID on the management bridge so the reservation matches eno1.
  systemd.network.networks."30-brvlan30" = {
    matchConfig.Name = "brvlan30";
    dhcpV4Config.ClientIdentifier = "mac";
  };

  homelab.personalServer = {
    enable = true;
    managementPubKey = "ssh/srv1-personal-mgmt.pub";
    usePasswordAuth = false;
  };

  lukasf.nixCache = {
    enable = true;
    secretKeyFile = "nix-cache/nix-serve.key";
    publicKey = builtins.readFile ../../../resources/nix-cache/personal-cache.pub;
    openFirewall = true;
    configureClient = true;
  };

  lukasf.serverDeployment.enableComin = true;

  lukasf.seaweedfs.enable = false;

  lukasf.ceph = {
    enable = true;
    monHosts = cephCluster.monHosts or [ cephCluster.monIp ];
    monPort = cephCluster.monPort or 3300;
    bootstrap = {
      enable = hasRole "bootstrap";
      fsid = cephCluster.fsid;
      monIp = cephCluster.monIp;
      publicNetwork = cephCluster.publicNetwork;
      singleHostDefaults = cephCluster.bootstrap.singleHostDefaults;
      skipDashboard = cephCluster.bootstrap.skipDashboard;
      extraArgs = cephCluster.bootstrap.extraArgs;
    };
    pools = lib.optionals (hasRole "bootstrap") cephCluster.pools;
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
      legacyAddress = "10.1.30.5";
    };
    healthCheck = {
      enable = true;
      checkLibvirt = hasRole "kvm";
      libvirtPools = [
        "ceph-images"
        "ceph-vmdisks"
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

  # GitHub PAT for Flux GitOps
  sops.secrets."flux-cluster-token" = {
    sopsFile = "${secrets.profileShared}/homelab/flux-cluster-dev/flux-cluster-bootstrap-token.txt";
    owner = "root";
    format = "binary";
    mode = "0400";
  };

  # Enable k3s with Flux GitOps
  homelab.kubernetes = {
    enable = true;
    extraK3sFlags = [
      "--tls-san srv1.lab.h4xx.io"
      "--tls-san srv1"
      "--tls-san 10.1.30.12"
    ];
    gitops = {
      enable = true;
      repoURL = "https://github.com/lukasfriedhoff/flux-cluster.git";
      branch = "develop";
      path = "./overlays/homelab";
      tokenFile = config.sops.secrets."flux-cluster-token".path;
      username = "lukasfriedhoff";
      sourceName = "flux-cluster";
      kustomizationName = "homelab";
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  sops.age.keyFile = "/var/lib/sops-nix/age/keys.txt";

  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeys = [ (builtins.readFile ./initrd-authorized.pub) ];
      hostKeys = [ "/etc/ssh/ssh_host_ed25519_key" ];
    };
  };

  users.users.root.openssh.authorizedKeys.keys = [ (builtins.readFile ./initrd-authorized.pub) ];
  users.users.nixos.openssh.authorizedKeys.keys = [ (builtins.readFile ./initrd-authorized.pub) ];

  networking.firewall.allowedTCPPorts = [ 4243 ];

  networking.extraHosts = ''
    # srv1 srv1.lab.h4xx.io 10.1.30.12
  '';
}
