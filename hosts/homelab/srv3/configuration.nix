{
  config,
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
    cephadm.unitDir = "/run/systemd/system";
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
      # Reprovision helper: keep enabled until OSDs are recreated once.
      # The ceph module writes a marker to skip further destructive zaps.
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
      path = "./overlays/testing-srv3";
      sopsAgeKeyFile = config.sops.secrets."flux-sops-age-key".path;
      sourceName = "flux-cluster";
      kustomizationName = "testing";
    };
  };

  sops.secrets."flux-sops-age-key" = {
    sopsFile = ../../../secrets/profiles/personal/servers/srv3/flux-sops-age.key;
    format = "json";
    key = "data";
    mode = "0400";
    owner = "root";
  };

  sops.secrets."srv3-bootstrap-password" = {
    sopsFile = ../../../secrets/profiles/personal/servers/srv3/bootstrap-password.txt;
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  systemd.services.srv3-bootstrap-password = {
    description = "Apply srv3 bootstrap password from SOPS secret";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      secret="${config.sops.secrets."srv3-bootstrap-password".path}"
      if [ ! -s "$secret" ]; then
        exit 0
      fi

      password="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$secret")"
      if [ -z "$password" ]; then
        echo "srv3 bootstrap password secret is empty" >&2
        exit 1
      fi

      ${pkgs.shadow}/bin/chpasswd <<EOF
      root:$password
      nixos:$password
      EOF
    '';
  };

  # Needed by cephadm to satisfy asyncssh dependency for health checks.
  environment.systemPackages = with pkgs; [
    python3Packages.asyncssh
  ];

  # `ceph orch` is unavailable on this single-node demo cluster; bootstrap an
  # MDS keyring and run one local MDS daemon so CephFS can come online.
  systemd.services."ceph-mds-${hostName}-keyring" = lib.mkIf (hasRole "bootstrap") {
    description = "Ensure Ceph MDS keyring for ${hostName}";
    wantedBy = [ "multi-user.target" ];
    wants = [ "cephadm-cephfs.service" ];
    after = [ "cephadm-cephfs.service" ];
    path = [ pkgs.ceph ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      keyring_dir="/var/lib/ceph/mds/ceph-${hostName}"
      keyring_path="$keyring_dir/keyring"
      mkdir -p "$keyring_dir"
      ceph auth get-or-create "mds.${hostName}" \
        mon 'allow profile mds' \
        osd 'allow rw tag cephfs *=*' \
        mds 'allow' \
        -o "$keyring_path"
      chown -R ceph:ceph "$keyring_dir"
    '';
  };

  systemd.services."ceph-mds-${hostName}-start" = lib.mkIf (hasRole "bootstrap") {
    description = "Start Ceph MDS instance ${hostName}";
    wantedBy = [ "multi-user.target" ];
    wants = [ "ceph-mds-${hostName}-keyring.service" ];
    after = [ "ceph-mds-${hostName}-keyring.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      systemctl start ceph-mds@${hostName}.service
    '';
  };

  networking.firewall.allowedTCPPorts = [ 4243 ];

  networking.extraHosts = ''
    # srv3 srv3.lab.h4xx.io
  '';
}
