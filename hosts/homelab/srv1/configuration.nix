{
  config,
  inputs,
  lib,
  secrets,
  ...
}:

let
  hostName = "srv1";
  clusterDomain = "lab.h4xx.io";
  prodApiHost = "srv9.lab.h4xx.io";
  k3sTokenSecret = "${secrets.primary}/k3s-server-token.txt";
  hasK3sToken = builtins.pathExists k3sTokenSecret;
in
{
  # Pure homelab k3s node (like srv2/srv8/srv9). The former gaming/Wolf +
  # ollama/open-webui + nix-cache + remote-builder roles were removed: they
  # pulled internet-download FODs (claude, discord, the wolf desktop-container
  # tarball) that this server VLAN cannot reach and that are not in Attic, so
  # the closure was unbuildable on-node. A lean node builds cleanly anywhere.
  imports = [
    inputs.disko.nixosModules.disko
    ../../common/default.nix
    ../common.nix
    ./disko.nix
  ];

  # Hardware comes from ./facter.json (the facter module auto-enables when it
  # exists); no hardware-configuration.nix import.

  networking.hostName = hostName;
  shared.network.domain = clusterDomain;

  homelab.vlanBridges = {
    enable = true;
    uplink = "eno1";
    mgmtMac = "0c:c4:7a:6c:38:02";
    # Pin the mgmt bridge MAC to the reserved mgmt MAC so brvlan30 gets the
    # DHCP reservation 10.1.30.12 (matches homelab.kubernetes.nodeIP) instead
    # of a random-MAC lease, and carry the same RouteMetric/static-route setup
    # as srv2/srv8/srv9. (Verified 2026-09-13: without pinBridgeMac the fresh
    # install came up on 10.1.30.32/10.1.20.105/10.1.40.234 and k3s wedged on
    # the dead nodeIP.)
    pinBridgeMac = true;
    routeMetrics = true;
  };

  networking.extraHosts = ''
    10.1.30.26 srv2 srv2.lab.h4xx.io
    10.1.30.12 srv1 srv1.lab.h4xx.io
  '';

  homelab.personalServer = {
    enable = true;
    managementPubKey = "ssh/srv1-personal-mgmt.pub";
    usePasswordAuth = false;
  };

  # k8s node: no swap (etcd fsync latency + kubelet semantics); the disko
  # swap partition stays dormant.
  swapDevices = lib.mkForce [ ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  sops.age.keyFile = "/var/lib/sops-nix/age/keys.txt";

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  # Only cryptroot is unlocked in initrd; the 5 longhorn LUKS devices are
  # unlocked in stage 2 by srv1-longhorn-disks.service (disko would otherwise
  # prompt for all of them before the root passphrase).
  boot.initrd.luks.devices = lib.mkForce {
    cryptroot = {
      device = "/dev/disk/by-partlabel/disk-main-root";
      allowDiscards = true;
    };
  };

  # 5x T-FORCE 1TB SATA SSDs as LUKS-encrypted Longhorn data disks (registered
  # purpose=longhorn in resources/homelab/disks.nix).
  homelab.longhornDisks = {
    enable = true;
    sopsFile = "${secrets.profileShared}/luks/srv1-longhorn.txt";
  };

  # Shared cluster k3s token: joins srv1 to the existing homelab cluster as an
  # AGENT (worker + Longhorn SSD storage; control-plane/etcd stays srv2/8/9).
  # Gated on token presence so a tokenless build can't accidentally clusterInit
  # a rogue single-node cluster.
  sops.secrets."k3s-server-token" = lib.mkIf hasK3sToken {
    sopsFile = k3sTokenSecret;
    owner = "root";
    format = "binary";
    mode = "0400";
  };

  # Control-plane member since 2026-09-21 (replaces srv2's etcd seat: srv2's
  # DRAM-less NVMe made etcd chronically slow). gitops bootstrap stays on the
  # existing servers.
  homelab.kubernetes = lib.mkIf hasK3sToken {
    enable = true;
    longhorn.enable = true;
    role = "server";
    # k3s refuses joins when critical flags differ between servers - the
    # existing control planes all run the embedded registry (Spegel).
    embeddedRegistry = true;
    # Broadwell Xeon tower with the SSD fast tier — batch-capable, unlike
    # the USB-disk minis (srv2/srv8).
    powerClass = "performance";
    serverAddr = "https://${prodApiHost}:6443";
    tokenFile = config.sops.secrets."k3s-server-token".path;
    nodeIP = "10.1.30.12";
    tlsSans = [
      "prod.k8s.lab.h4xx.io"
      "srv1.lab.h4xx.io"
      "srv1"
      "10.1.30.12"
    ];
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
