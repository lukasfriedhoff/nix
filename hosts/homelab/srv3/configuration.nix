{
  config,
  secrets,
  inputs,
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

  lukasf.kvm.enable = true;

  homelab.kubernetes = {
    enable = true;
    longhorn.enable = true;
    tlsSans = [
      "srv3.lab.h4xx.io"
      "srv3"
    ];
    nodeLabels = [
      "h4xx.io/gpu.present=false"
      "h4xx.io/gpu.vendor=virtual"
      "h4xx.io/gpu.vaapi=false"
    ];
    extraFlags = [ "--kubelet-arg=max-pods=250" ];
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
    sopsFile = "${secrets.primary}/flux-cluster-bootstrap-token.txt";
    owner = "root";
    format = "binary";
    mode = "0400";
  };

  sops.secrets."flux-sops-age-key" = {
    sopsFile = "${secrets.primary}/flux-sops-age.key";
    format = "json";
    key = "data";
    mode = "0400";
    owner = "root";
  };

  homelab.bootstrapPassword = {
    enable = true;
    secretName = "srv3-bootstrap-password";
    sopsFile = "${secrets.primary}/bootstrap-password.txt";
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
