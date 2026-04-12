{
  config,
  lib,
  pkgs,
  secrets ? { },
  linuxUser ? "lukasf",
  ...
}:

let
  cfg = config.desktop.personalWorkstation;

  primaryRoot = secrets.primary or secrets.root or null;

  wireguardKeyFile = if primaryRoot != null then "${primaryRoot}/wireguard/homelab.priv" else null;

  hasWireguardKey = wireguardKeyFile != null && builtins.pathExists wireguardKeyFile;

  inherit (cfg) cephClientName;

  cephKeyringFile =
    if cephClientName != null && primaryRoot != null then
      "${primaryRoot}/ceph/client.${cephClientName}.keyring.txt"
    else
      null;

  hasCephKeyring = cephKeyringFile != null && builtins.pathExists cephKeyringFile;

  cephSystemKeyringPath =
    if cephClientName != null then "/etc/ceph/ceph.client.${cephClientName}.keyring" else null;

  cephUserKeyringPath =
    if cephClientName != null then
      "/home/${linuxUser}/.ceph/ceph.client.${cephClientName}.keyring"
    else
      null;

  cephSystemSecretName =
    if cephClientName != null then "ceph/client-${cephClientName}-keyring" else null;

  cephUserSecretName =
    if cephClientName != null then "ceph/client-${cephClientName}-keyring-user" else null;
in
{
  options.desktop.personalWorkstation = {
    enable = lib.mkEnableOption "personal desktop workstation app stack";

    wireguardAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "WireGuard homelab address (CIDR) for this workstation.";
    };

    cephClientName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Ceph client name used for keyring and sops secret names.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        desktop.gaming.enable = true;

        lukasf.ollama = {
          enable = true;
          autoStart = false;
          ui.autoStart = false;
        };

        lukasf.protonvpn.enable = true;

        virtualisation.podman = {
          enable = true;
          dockerCompat = true;
          defaultNetwork.settings = {
            dns_enabled = true;
          };
        };

        environment.systemPackages = with pkgs; [
          libvirt
          ceph
          android-tools
          scrcpy
          podman-compose
        ];

        # Allow dynamic binaries from third-party installers (e.g., oh-my-opencode CLI).
        programs.nix-ld = {
          enable = true;
          libraries = with pkgs; [
            stdenv.cc.cc
            glibc
            openssl
            zlib
          ];
        };

        systemd.tmpfiles.rules = [
          "d /home/${linuxUser}/.ceph 0700 ${linuxUser} users -"
          "d /var/lib/sops-nix/ssh 0700 root root -"
        ];
      }
      (lib.mkIf (cfg.wireguardAddress != null && hasWireguardKey) {
        desktop.wireguardHomelab = {
          enable = true;
          address = cfg.wireguardAddress;
        };
      })
      (lib.mkIf (cfg.cephClientName != null) {
        lukasf.ceph.client = {
          enable = true;
          monHosts = [ "srv1.lab.h4xx.io" ];
          monPort = 3300;
          publicNetwork = "10.1.30.0/24";
        };
      })
      (lib.mkIf (cfg.cephClientName != null && hasCephKeyring) {
        sops.secrets.${cephSystemSecretName} = {
          sopsFile = cephKeyringFile;
          owner = "root";
          mode = "0400";
          path = cephSystemKeyringPath;
          format = "binary";
        };

        sops.secrets.${cephUserSecretName} = {
          sopsFile = cephKeyringFile;
          owner = linuxUser;
          mode = "0600";
          path = cephUserKeyringPath;
          format = "binary";
        };
      })
    ]
  );
}
