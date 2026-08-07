{
  authorizedKeyFile,
  bootstrap,
  macAddress,
  nodeIndex,
  nodeIP,
  nodeName,
  priority,
}:

{
  config,
  secrets,
  inputs,
  lib,
  ...
}:

let
  clusterDomain = "testingrke2.lab.h4xx.io";
  clusterNetwork = "192.168.124.0/24";
  gateway = "192.168.124.1";
  virtualIP = "192.168.124.10";
  interface = "enp1s0";
  nodeIPs = [
    "192.168.124.11"
    "192.168.124.12"
    "192.168.124.13"
  ];
  nodeNames = [
    "testingrke2-01"
    "testingrke2-02"
    "testingrke2-03"
  ];
  rootSerial = "trke2-${toString nodeIndex}-root";
  longhornSerial = "trke2-${toString nodeIndex}-lh1";
in
{
  imports = [
    inputs.disko.nixosModules.disko
    ../../common/default.nix
    ../common.nix
    ./hardware-configuration.nix
    (import ./disko.nix {
      inherit longhornSerial rootSerial;
    })
  ];

  assertions = [
    {
      assertion = nodeIndex >= 1 && nodeIndex <= builtins.length nodeIPs;
      message = "testingrke2 nodeIndex must be between 1 and ${toString (builtins.length nodeIPs)}.";
    }
    {
      assertion = builtins.elem nodeName nodeNames;
      message = "testingrke2 nodeName must be one of the declared cluster nodes.";
    }
    {
      assertion = builtins.elem nodeIP nodeIPs;
      message = "testingrke2 nodeIP must be one of the declared cluster addresses.";
    }
  ];

  networking = {
    hostName = nodeName;
    useDHCP = false;
    defaultGateway = {
      address = gateway;
      inherit interface;
    };
    nameservers = [
      gateway
      "1.1.1.1"
    ];
    interfaces.${interface} = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = nodeIP;
          prefixLength = 24;
        }
      ];
    };
    extraHosts = ''
      ${virtualIP} testingrke2-api testingrke2-api.${clusterDomain}
      ${builtins.concatStringsSep "\n" (
        builtins.genList (
          index:
          let
            name = builtins.elemAt nodeNames index;
            ip = builtins.elemAt nodeIPs index;
          in
          "${ip} ${name} ${name}.${clusterDomain}"
        ) (builtins.length nodeNames)
      )}
    '';
  };
  shared.network.domain = clusterDomain;

  homelab.personalServer = {
    enable = true;
    managementPubKey = null;
    usePasswordAuth = false;
  };

  users.users.root.openssh.authorizedKeys.keyFiles = [ authorizedKeyFile ];
  users.users.nixos.openssh.authorizedKeys.keyFiles = [ authorizedKeyFile ];

  boot = {
    loader.systemd-boot.enable = true;
    loader.efi.canTouchEfiVariables = true;
    kernelParams = [
      "console=tty0"
      "console=ttyS0,115200n8"
      "console=ttyS1,115200n8"
    ];
    initrd.network.udhcpc = {
      enable = true;
      extraArgs = [
        "-t"
        "20"
        "-T"
        "3"
        "-x"
        "0x3d:01${builtins.replaceStrings [ ":" ] [ "" ] macAddress}"
        "-x"
        "hostname:${nodeName}"
      ];
    };
  };

  homelab.initrdSsh = {
    enable = true;
    inherit authorizedKeyFile;
  };

  lukasf.remoteBuilds.enable = false;
  lukasf.privateNix.enable = false;

  homelab.kubernetes = {
    enable = true;
    distribution = "rke2";
    role = "server";
    serverAddr = if bootstrap then null else "https://${virtualIP}:9345";
    tokenFile = config.sops.secrets."rke2-token".path;
    inherit nodeIP nodeName;
    nodeLabels = [
      "h4xx.io/cluster=testingrke2"
      "h4xx.io/gpu.present=false"
      "h4xx.io/gpu.vendor=virtual"
      "h4xx.io/gpu.vaapi=false"
      "h4xx.io/storage.longhorn=true"
    ];
    tlsSans = [
      virtualIP
      "testingrke2-api"
      "testingrke2-api.${clusterDomain}"
    ]
    ++ nodeIPs
    ++ nodeNames
    ++ map (name: "${name}.${clusterDomain}") nodeNames;
    extraFlags = [
      "--flannel-iface=${interface}"
      "--kubelet-arg=max-pods=250"
    ];
    longhorn.enable = true;
    rke2 = {
      cni = "canal";
      disable = [ "rke2-ingress-nginx" ];
    };
    highAvailability = {
      enable = true;
      inherit
        interface
        nodeIPs
        priority
        virtualIP
        ;
      virtualIPPrefixLength = 24;
      virtualRouterId = 72;
    };
    gitops = {
      enable = bootstrap;
      repoURL = "https://github.com/lukasfriedhoff/flux-cluster.git";
      branch = "testing";
      path = "./overlays/testingrke2";
      tokenFile = if bootstrap then config.sops.secrets."flux-cluster-token".path else null;
      sopsAgeKeyFile = if bootstrap then config.sops.secrets."flux-sops-age-key".path else null;
      username = "lukasfriedhoff";
      sourceName = "flux-cluster";
      kustomizationName = "testingrke2";
    };
  };

  sops.secrets = {
    "rke2-token" = {
      sopsFile = "${secrets.primary}/rke2-token.txt";
      format = "binary";
      mode = "0400";
      owner = "root";
    };
  }
  // lib.optionalAttrs bootstrap {
    "flux-cluster-token" = {
      sopsFile = "${secrets.primary}/flux-cluster-bootstrap-token.txt";
      format = "binary";
      mode = "0400";
      owner = "root";
    };

    "flux-sops-age-key" = {
      sopsFile = "${secrets.primary}/flux-sops-age.key";
      format = "binary";
      mode = "0400";
      owner = "root";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/longhorn-disk1 0750 root root -"
  ];

  environment.etc."testingrke2/topology.json".text = builtins.toJSON {
    cluster = "testingrke2";
    inherit
      clusterNetwork
      gateway
      nodeIP
      nodeName
      virtualIP
      ;
    nodes = builtins.listToAttrs (
      builtins.genList (index: {
        name = builtins.elemAt nodeNames index;
        value = builtins.elemAt nodeIPs index;
      }) (builtins.length nodeNames)
    );
  };
}
