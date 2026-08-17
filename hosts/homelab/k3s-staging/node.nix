# Parameterized node function for the srv5/srv6/srv7 k3s staging cluster.
# Per-host directories stay thin: they import this function with the node's
# identity and keep only distinct files (initrd-authorized.pub).
{
  authorizedKeyFile,
  bootstrap,
  longhornBind ? false,
  macAddress,
  nodeIP,
  nodeName,
}:

{
  config,
  secrets,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  nets = import ../../../resources/homelab/networks.nix;
  clusterDomain = "lab.h4xx.io";
  stagingApiHost = "k3s-staging-api.lab.h4xx.io";
  interface = "enp1s0";
  gateway = nets.vlans.mgmt.gateway;
  nodeNames = [
    "srv5-k3s-stg1"
    "srv6-k3s-stg2"
    "srv7-k3s-stg3"
  ];
  nodeIPs = [
    "10.1.30.18"
    "10.1.30.19"
    "10.1.30.22"
  ];
  clusterNodes = map (name: "${name}.${clusterDomain}") nodeNames;
  apiNode = builtins.head nodeNames;
  # Short host label (srv5/srv6/srv7) used for DHCP and secret names.
  shortName = builtins.head (lib.splitString "-" nodeName);
in
{
  imports = [
    inputs.disko.nixosModules.disko
    ../../common/default.nix
    ../common.nix
    ./hardware-configuration.nix
    ./disko.nix
  ];

  assertions = [
    {
      assertion = builtins.elem nodeName nodeNames;
      message = "k3s-staging nodeName must be one of the declared cluster nodes.";
    }
    {
      assertion = builtins.elem nodeIP nodeIPs;
      message = "k3s-staging nodeIP must be one of the declared cluster addresses.";
    }
  ];

  networking.hostName = nodeName;
  networking.extraHosts = builtins.concatStringsSep "\n" (
    builtins.genList (
      index:
      let
        name = builtins.elemAt nodeNames index;
        ip = builtins.elemAt nodeIPs index;
      in
      "${ip} ${name} ${name}.${clusterDomain}${lib.optionalString (name == apiNode) " ${stagingApiHost}"}"
    ) (builtins.length nodeNames)
  );
  networking.useDHCP = false;
  networking.interfaces.${interface}.useDHCP = true;
  networking.dhcpcd.allowInterfaces = [ interface ];
  networking.defaultGateway = {
    address = gateway;
    inherit interface;
  };
  shared.network.domain = clusterDomain;

  homelab.personalServer = {
    enable = true;
    managementPubKey = null;
    usePasswordAuth = false;
  };

  users.users.root.openssh.authorizedKeys.keyFiles = [ authorizedKeyFile ];
  users.users.nixos.openssh.authorizedKeys.keyFiles = [ authorizedKeyFile ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.initrdSsh = {
    enable = true;
    inherit authorizedKeyFile;
  };

  boot.initrd.network.udhcpc.enable = true;
  boot.initrd.network.udhcpc.extraArgs = [
    "-t"
    "20"
    "-T"
    "3"
    "-x"
    # DHCP option 61 (client identifier): 01 + mgmt MAC (no separators)
    "0x3d:01${builtins.replaceStrings [ ":" ] [ "" ] macAddress}"
    "-x"
    "hostname:${shortName}"
  ];

  homelab.kubernetes = {
    enable = true;
    longhorn.enable = true;
    clusterInit = bootstrap;
    serverAddr = if bootstrap then null else "https://${stagingApiHost}:6443";
    tokenFile = config.sops.secrets."k3s-server-token".path;
    inherit nodeIP;
    nodeLabels = [
      "h4xx.io/gpu.present=false"
      "h4xx.io/gpu.vendor=virtual"
      "h4xx.io/gpu.vaapi=false"
    ];
    tlsSans = [
      stagingApiHost
      nodeName
      "${nodeName}.${clusterDomain}"
    ]
    ++ clusterNodes;
    extraFlags = [
      "--flannel-iface ${interface}"
      "--kubelet-arg=max-pods=250"
    ];
    gitops = {
      enable = bootstrap;
      repoURL = "https://github.com/lukasfriedhoff/flux-cluster.git";
      branch = "develop";
      path = "./overlays/staging-3vm";
      sopsAgeKeyFile = if bootstrap then config.sops.secrets."flux-sops-age-key".path else null;
      sourceName = "flux-cluster";
      kustomizationName = "staging-3vm";
    };
  };

  systemd.services.longhorn-data-disk-bind = lib.mkIf longhornBind {
    description = "Bind Longhorn default data path to ${nodeName} data disk";
    before = [ "k3s.service" ];
    requiredBy = [ "k3s.service" ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.RequiresMountsFor = "/var/lib/longhorn-disk1";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      mkdir -p /var/lib/longhorn-disk1/longhorn /var/lib/longhorn
      if ! ${pkgs.util-linux}/bin/mountpoint -q /var/lib/longhorn; then
        ${pkgs.util-linux}/bin/mount --bind /var/lib/longhorn-disk1/longhorn /var/lib/longhorn
      fi
    '';
  };

  sops.secrets = {
    "k3s-server-token" = {
      sopsFile = "${secrets.primary}/k3s-server-token.txt";
      format = "binary";
      mode = "0400";
      owner = "root";
    };
  }
  // lib.optionalAttrs bootstrap {
    "flux-sops-age-key" = {
      sopsFile = "${secrets.primary}/flux-sops-age.key";
      format = "binary";
      mode = "0400";
      owner = "root";
    };
  };

  homelab.bootstrapPassword = {
    enable = true;
    secretName = "${shortName}-bootstrap-password";
    sopsFile = "${secrets.primary}/bootstrap-password.txt";
  };
}
