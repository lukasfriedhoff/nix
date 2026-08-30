{
  config,
  secrets,
  inputs,
  lib,
  ...
}:

let
  hostName = "srv9";
  clusterDomain = "lab.h4xx.io";
  prodApiHost = "srv2.lab.h4xx.io";
  managementInterface = "eno1np0";
  managementMac = "e4:43:4b:f2:1a:42";
  systemDiskId = "scsi-35002538b11337b60";
  k3sTokenSecret = "${secrets.primary}/k3s-server-token.txt";
  loginPasswordHashSecret = "${secrets.primary}/login-password-hash.txt";
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
    uplink = managementInterface;
    mgmtMac = managementMac;
  };

  homelab.personalServer = {
    enable = true;
    managementPubKey = null;
    usePasswordAuth = false;
  };

  users.users = {
    root = {
      initialHashedPassword = lib.mkForce null;
      hashedPasswordFile = config.sops.secrets."srv9-login-password-hash".path;
      openssh.authorizedKeys.keyFiles = [ ./initrd-authorized.pub ];
    };
    nixos.openssh.authorizedKeys.keyFiles = [ ./initrd-authorized.pub ];
    lukasf = {
      isNormalUser = true;
      group = "users";
      extraGroups = [
        "sudo"
        "wheel"
      ];
      hashedPasswordFile = config.sops.secrets."srv9-login-password-hash".path;
    };
  };
  users.groups.sudo = { };

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    initrd = {
      availableKernelModules = lib.mkAfter [
        "i40e"
        "igb"
        "megaraid_sas"
      ];
      kernelModules = [
        "i40e"
        "megaraid_sas"
      ];
      network.udhcpc = {
        enable = true;
        extraArgs = [
          "-i"
          managementInterface
          "-t"
          "20"
          "-T"
          "3"
          "-x"
          "0x3d:01e4434bf21a42"
          "-x"
          "hostname:srv9"
        ];
      };
      luks.devices = lib.mkForce {
        cryptroot = {
          device = "/dev/disk/by-id/${systemDiskId}-part2";
          allowDiscards = true;
        };
      };
    };
  };

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  sops.secrets = {
    "srv9-login-password-hash" = {
      sopsFile = loginPasswordHashSecret;
      format = "binary";
      neededForUsers = true;
    };
    "k3s-server-token" = lib.mkIf hasK3sToken {
      sopsFile = k3sTokenSecret;
      format = "binary";
      mode = "0400";
      owner = "root";
    };
  };

  homelab.longhornDisks = {
    enable = true;
    sopsFile = "${secrets.profileShared}/luks/srv9-longhorn.txt";
    mode = "0755";
  };

  homelab.kubernetes = lib.mkIf hasK3sToken {
    enable = true;
    longhorn.enable = true;
    embeddedRegistry = true;
    # Control-plane peer: joins srv2's embedded etcd. srv2 must be migrated
    # off sqlite (clusterInit) before this role change is deployed
    # (docs/deployment/k3s-ha-migration.md).
    role = "server";
    serverAddr = "https://${prodApiHost}:6443";
    tokenFile = config.sops.secrets."k3s-server-token".path;
    nodeName = hostName;
    nodeIP = "10.1.30.31";
    tlsSans = [
      "srv9.lab.h4xx.io"
      "srv9"
      "10.1.30.31"
    ];
    extraFlags = [ "--kubelet-arg=max-pods=250" ];
  };
}
