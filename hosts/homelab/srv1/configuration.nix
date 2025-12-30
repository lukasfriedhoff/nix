{
  config,
  inputs,
  lib,
  secrets,
  ...
}:

let
  seaweedDisks = import ../../../resources/seaweedfs/srv1-disks.nix;
  seaweedDiskIds = map builtins.baseNameOf seaweedDisks;
  seaweedKeySecrets = lib.listToAttrs (
    map (diskId: {
      name = "seaweedfs-${diskId}-key";
      value = {
        sopsFile = "${secrets.primary}/seaweedfs/${diskId}.key";
        owner = "root";
        format = "binary";
        mode = "0400";
      };
    }) seaweedDiskIds
  );
  seaweedKeyFiles = lib.genAttrs seaweedDiskIds (
    diskId: config.sops.secrets."seaweedfs-${diskId}-key".path
  );
in
{
  imports = [
    inputs.disko.nixosModules.disko
    ./hardware-configuration.nix
    ./disko.nix
  ];

  networking.hostName = "srv1";
  networking.domain = "h4xx.local";

  homelab.personalServer = {
    enable = true;
    managementPubKey = "ssh/srv1-personal-mgmt.pub";
    usePasswordAuth = false;
  };

  sops.secrets = seaweedKeySecrets;

  lukasf.nixCache = {
    enable = true;
    secretKeyFile = "nix-cache/nix-serve.key";
    publicKey = builtins.readFile ../../../resources/nix-cache/personal-cache.pub;
    openFirewall = true;
    configureClient = true;
  };

  lukasf.serverDeployment.enableComin = true;

  lukasf.seaweedfs = {
    enable = true;
    roles = [
      "master"
      "volume"
      "filer"
    ];
    cluster.defaultReplication = "000";
    volume = {
      disks = seaweedDisks;
      mountBase = "/mnt/seaweedfs";
      filesystem = "xfs";
      formatIfMissing = true;
      encryption = {
        enable = true;
        keyFiles = seaweedKeyFiles;
      };
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
    # srv1 srv1.h4xx.local 10.1.30.12
  '';
}
