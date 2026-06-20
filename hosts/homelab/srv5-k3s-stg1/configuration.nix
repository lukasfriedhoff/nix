{
  config,
  inputs,
  pkgs,
  ...
}:

let
  hostName = "srv5-k3s-stg1";
  clusterDomain = "lab.h4xx.io";
  stagingApiHost = "k3s-staging-api.lab.h4xx.io";
  clusterNodes = [
    "srv5-k3s-stg1.lab.h4xx.io"
    "srv6-k3s-stg2.lab.h4xx.io"
    "srv7-k3s-stg3.lab.h4xx.io"
  ];
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
  networking.extraHosts = ''
    10.1.30.18 srv5-k3s-stg1 srv5-k3s-stg1.lab.h4xx.io k3s-staging-api.lab.h4xx.io
    10.1.30.19 srv6-k3s-stg2 srv6-k3s-stg2.lab.h4xx.io
    10.1.30.22 srv7-k3s-stg3 srv7-k3s-stg3.lab.h4xx.io
  '';
  networking.useDHCP = false;
  networking.interfaces.enp1s0.useDHCP = true;
  networking.dhcpcd.allowInterfaces = [ "enp1s0" ];
  networking.defaultGateway = {
    address = "10.1.30.1";
    interface = "enp1s0";
  };
  shared.network.domain = clusterDomain;

  homelab.personalServer = {
    enable = true;
    managementPubKey = null;
    usePasswordAuth = false;
  };

  users.users.root.openssh.authorizedKeys.keyFiles = [ ./initrd-authorized.pub ];
  users.users.nixos.openssh.authorizedKeys.keyFiles = [ ./initrd-authorized.pub ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  homelab.initrdSsh = {
    enable = true;
    authorizedKeyFile = ./initrd-authorized.pub;
  };

  boot.initrd.network.udhcpc.enable = true;
  boot.initrd.network.udhcpc.extraArgs = [
    "-t"
    "20"
    "-T"
    "3"
    "-x"
    # DHCP option 61 (client identifier): 01 + mgmt MAC (52:54:00:be:0f:f4)
    "0x3d:01525400be0ff4"
    "-x"
    "hostname:srv5"
  ];

  homelab.kubernetes = {
    enable = true;
    longhorn.enable = true;
    extraK3sFlags = [
      "--cluster-init"
      "--token-file=${config.sops.secrets."k3s-server-token".path}"
      "--tls-san ${stagingApiHost}"
      "--tls-san ${hostName}"
      "--tls-san ${hostName}.${clusterDomain}"
      "--node-ip 10.1.30.18"
      "--flannel-iface enp1s0"
      "--kubelet-arg=max-pods=250"
    ]
    ++ map (node: "--tls-san ${node}") clusterNodes;
    gitops = {
      enable = true;
      repoURL = "https://github.com/lukasfriedhoff/flux-cluster.git";
      branch = "develop";
      path = "./overlays/staging-3vm";
      sopsAgeKeyFile = config.sops.secrets."flux-sops-age-key".path;
      sourceName = "flux-cluster";
      kustomizationName = "staging-3vm";
    };
  };

  sops.secrets."k3s-server-token" = {
    sopsFile = ../../../secrets/profiles/personal/servers/srv5-k3s-stg1/k3s-server-token.txt;
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  sops.secrets."flux-sops-age-key" = {
    sopsFile = ../../../secrets/profiles/personal/servers/srv5-k3s-stg1/flux-sops-age.key;
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  sops.secrets."srv5-bootstrap-password" = {
    sopsFile = ../../../secrets/profiles/personal/servers/srv5-k3s-stg1/bootstrap-password.txt;
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  systemd.services.srv5-bootstrap-password = {
    description = "Apply srv5 bootstrap password from SOPS secret";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      secret="${config.sops.secrets."srv5-bootstrap-password".path}"
      if [ ! -s "$secret" ]; then
        exit 0
      fi

      password="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$secret")"
      if [ -z "$password" ]; then
        echo "srv5 bootstrap password secret is empty" >&2
        exit 1
      fi

      ${pkgs.shadow}/bin/chpasswd <<EOF
      root:$password
      nixos:$password
      EOF
    '';
  };
}
