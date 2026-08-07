{
  config,
  secrets,
  inputs,
  pkgs,
  ...
}:

let
  hostName = "srv6-k3s-stg2";
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
    # DHCP option 61 (client identifier): 01 + mgmt MAC (52:54:00:0b:b2:6c)
    "0x3d:015254000bb26c"
    "-x"
    "hostname:srv6"
  ];

  homelab.kubernetes = {
    enable = true;
    longhorn.enable = true;
    extraK3sFlags = [
      "--server https://${stagingApiHost}:6443"
      "--token-file=${config.sops.secrets."k3s-server-token".path}"
      "--tls-san ${stagingApiHost}"
      "--tls-san ${hostName}"
      "--tls-san ${hostName}.${clusterDomain}"
      "--node-ip 10.1.30.19"
      "--node-label=h4xx.io/gpu.present=false"
      "--node-label=h4xx.io/gpu.vendor=virtual"
      "--node-label=h4xx.io/gpu.vaapi=false"
      "--flannel-iface enp1s0"
      "--kubelet-arg=max-pods=250"
    ]
    ++ map (node: "--tls-san ${node}") clusterNodes;
  };

  systemd.services.longhorn-data-disk-bind = {
    description = "Bind Longhorn default data path to srv6 data disk";
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

  sops.secrets."k3s-server-token" = {
    sopsFile = "${secrets.primary}/k3s-server-token.txt";
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  sops.secrets."srv6-bootstrap-password" = {
    sopsFile = "${secrets.primary}/bootstrap-password.txt";
    format = "binary";
    mode = "0400";
    owner = "root";
  };

  systemd.services.srv6-bootstrap-password = {
    description = "Apply srv6 bootstrap password from SOPS secret";
    wantedBy = [ "multi-user.target" ];
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail
      secret="${config.sops.secrets."srv6-bootstrap-password".path}"
      if [ ! -s "$secret" ]; then
        exit 0
      fi

      password="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$secret")"
      if [ -z "$password" ]; then
        echo "srv6 bootstrap password secret is empty" >&2
        exit 1
      fi

      ${pkgs.shadow}/bin/chpasswd <<EOF
      root:$password
      nixos:$password
      EOF
    '';
  };
}
