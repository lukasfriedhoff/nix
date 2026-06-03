{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  hostName = "srv3";
  builderUser = "nixbuilder";
  builderUid = 31000;
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

  users.groups.${builderUser} = { };
  users.users.${builderUser} = {
    isSystemUser = true;
    uid = builderUid;
    group = builderUser;
    createHome = true;
    home = "/var/lib/${builderUser}";
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [ (builtins.readFile ./initrd-authorized.pub) ];
  };

  nix.settings = {
    max-jobs = lib.mkForce 2;
    cores = lib.mkForce 2;
    trusted-users = lib.mkAfter [ builderUser ];
  };

  lukasf.remoteBuilds.enable = false;

  # Limit remote build sessions without throttling other services.
  systemd.slices."user-${toString builderUid}".sliceConfig = {
    CPUQuota = "500%";
    MemoryHigh = "48G";
    MemoryMax = "64G";
  };

  lukasf.nixCache = {
    enable = true;
    secretKeyFile = "nix-cache/nix-serve.key";
    publicKey = builtins.readFile ../../../resources/nix-cache/testing-cache.pub;
    openFirewall = true;
    configureClient = true;
    cacheHost = "nix-testing.h4xx.io";
    # Use loopback locally to avoid DNS dependency on the host itself.
    cacheUrl = "http://127.0.0.1:5000";
  };

  lukasf.atticCache = {
    enable = true;
    serve = true;
    configureClient = true;
    environmentFile = "attic/server.env";
    serverUrl = "http://attic.lab.h4xx.io:8080";
    cacheName = "homelab";
    listenAddress = "0.0.0.0:8080";
    port = 8080;
    openFirewall = true;
    postBuildUpload = {
      enable = true;
      serverAlias = "srv3";
      tokenSubject = "hydra";
    };
  };

  lukasf.hydraBuilder = {
    enable = true;
    hydraURL = "http://srv3.lab.h4xx.io:3000";
    listenHost = "0.0.0.0";
    port = 3000;
    openFirewall = true;
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

  fileSystems."/var/lib/longhorn-disk1" = {
    device = "/dev/disk/by-id/virtio-srv3-longhorn1";
    fsType = "ext4";
    options = [
      "defaults"
      "nofail"
      "discard"
    ];
  };

  lukasf.kvm = {
    enable = true;
    storage = {
      backend = "none";
    };
  };

  homelab.kubernetes = {
    enable = true;
    longhorn.enable = true;
    extraK3sFlags = [
      "--tls-san srv3.lab.h4xx.io"
      "--tls-san srv3"
      "--kubelet-arg=max-pods=250"
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

  networking.firewall = {
    # Expose moonlight-web hostNetwork listener and Moonlight client channels
    # so the Wolf host on srv4 can return stream traffic to srv3.
    allowedTCPPorts = [
      4243
      18080
      47984
      47989
      48010
    ];
    allowedUDPPorts = [
      47998
      47999
      48000
      48010
    ];
    allowedUDPPortRanges = [
      {
        from = 40000;
        to = 40100;
      }
    ];
  };

  networking.extraHosts = ''
    # srv3 srv3.lab.h4xx.io
  '';
}
