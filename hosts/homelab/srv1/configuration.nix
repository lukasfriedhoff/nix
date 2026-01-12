{
  config,
  inputs,
  lib,
  secrets,
  ...
}:

let
  hostName = "srv1";
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
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = hostName;
  networking.domain = "lab.h4xx.io";
  networking.interfaces.eno1 = {
    useDHCP = true;
    ipv4.addresses = [
      {
        address = "10.1.30.12";
        prefixLength = 24;
      }
    ];
  };
  networking.hosts = {
    "10.1.30.12" = [
      "srv1.lab.h4xx.io"
      "srv1"
    ];
    "127.0.0.2" = lib.mkForce [ ];
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
