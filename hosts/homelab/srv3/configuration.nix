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
    max-jobs = lib.mkForce 5;
    cores = lib.mkForce 4;
    experimental-features = lib.mkAfter [ "cgroups" ];
    use-cgroups = true;
    trusted-users = lib.mkAfter [ builderUser ];
  };

  lukasf.remoteBuilds.enable = false;

  # Limit remote build sessions without throttling other services.
  systemd.slices."user-${toString builderUid}".sliceConfig = {
    CPUQuota = "2200%";
    MemoryHigh = "60G";
    MemoryMax = "64G";
  };

  # Hydra runs as dedicated service users, but actual build processes are
  # spawned by nix-daemon as nixbld users. Put those builds behind an explicit
  # cgroup budget so Kubernetes and host services retain headroom.
  systemd.slices.hydra-builds = {
    description = "Hydra and Nix build workload budget";
    sliceConfig = {
      CPUQuota = "2200%";
      MemoryHigh = "60G";
      MemoryMax = "64G";
    };
  };

  systemd.services.nix-daemon.serviceConfig.Slice = "hydra-builds.slice";

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
    serve = false;
    configureClient = false;
    environmentFile = "attic/server.env";
    serverUrl = "https://attic-testing.h4xx.io";
    cacheName = "homelab";
    openFirewall = false;
    postBuildUpload = {
      enable = true;
      automaticDrain = true;
      uploadInterval = "5min";
      batchFileLimit = 100;
      serverAlias = "srv3";
      serverUrl = "http://10.43.206.159:8080";
      tokenSubject = "hydra";
      uploadJobs = 1;
    };
  };

  sops.secrets."hydra-admin-password" = {
    sopsFile = ../../../secrets/profiles/personal/servers/srv3/hydra/admin-password.txt;
    format = "binary";
    mode = "0400";
    owner = "hydra";
  };

  lukasf.hydraBuilder = {
    enable = true;
    hydraURL = "http://srv3.lab.h4xx.io:3000";
    listenHost = "0.0.0.0";
    port = 3000;
    openFirewall = true;
    adminPasswordFile = config.sops.secrets."hydra-admin-password".path;
    declarativeProjects.nixos-configs = {
      displayName = "NixOS Configurations";
      jobsets.all = {
        flake = "git+https://github.com/lukasfriedhoff/nix.git?ref=develop";
        description = "All NixOS host configurations";
        checkInterval = 3600;
        keepNr = 3;
      };
    };
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
    # Route attic uploads through Traefik (ClusterIP) instead of Cloudflare tunnel.
    # Cloudflare free tier rejects bodies >100MB; large NARs must bypass it.
    # Traefik handles TLS termination; cert is valid for attic-testing.h4xx.io.
    10.43.66.105 attic-testing.h4xx.io
  '';
}
