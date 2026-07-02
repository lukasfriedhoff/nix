{
  config,
  inputs,
  pkgs,
  ...
}:

let
  hostName = "srv3";
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

  lukasf.remoteBuilds.enable = false;

  lukasf.nixCache = {
    enable = false;
    secretKeyFile = "nix-cache/nix-serve.key";
    publicKey = builtins.readFile ../../../resources/nix-cache/testing-cache.pub;
    openFirewall = true;
    configureClient = true;
    cacheHost = "nix-testing.h4xx.io";
    # Use loopback locally to avoid DNS dependency on the host itself.
    cacheUrl = "http://127.0.0.1:5000";
  };

  lukasf.atticCache = {
    enable = false;
    serve = false;
    configureClient = false;
    environmentFile = "attic/server.env";
    serverUrl = "https://attic-testing.h4xx.io";
    cacheName = "homelab";
    openFirewall = false;
    postBuildUpload = {
      enable = false;
      automaticDrain = true;
      uploadInterval = "5min";
      batchFileLimit = 100;
      serverAlias = "srv3";
      serverUrl = "http://10.43.206.159:8080";
      tokenSubject = "hydra";
      uploadJobs = 1;
    };
  };

  lukasf.hydraBuilder = {
    enable = false;
    hydraURL = "http://srv3.lab.h4xx.io:3000";
    listenHost = "0.0.0.0";
    port = 3000;
    openFirewall = true;
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

  fileSystems."/var/lib/longhorn-disk2" = {
    device = "/dev/disk/by-id/virtio-srv3-longhorn2";
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
      tokenFile = config.sops.secrets."flux-cluster-token".path;
      sopsAgeKeyFile = config.sops.secrets."flux-sops-age-key".path;
      username = "lukasfriedhoff";
      sourceName = "flux-cluster";
      kustomizationName = "testing";
    };
  };

  sops.secrets."flux-cluster-token" = {
    sopsFile = ../../../secrets/profiles/personal/servers/srv3/flux-cluster-bootstrap-token.txt;
    owner = "root";
    format = "binary";
    mode = "0400";
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
