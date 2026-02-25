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
  profileCommonRoot = secrets.profileCommon or null;

  builderKeyFile =
    if profileCommonRoot != null then "${profileCommonRoot}/ssh/srv1-personal-mgmt.priv" else null;

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

  cachePublicKey = builtins.readFile ../../../../resources/nix-cache/personal-cache.pub;
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

        lukasf.nixCache = {
          enable = true;
          serve = false;
          configureClient = true;
          cacheHost = "srv1.lab.h4xx.io";
          publicKey = cachePublicKey;
          connectTimeout = 2;
          fallbackToOfficial = true;
        };

        # If the private cache is unreachable, build locally instead of aborting.
        nix.settings.fallback = true;

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

        shared.ssh.knownHosts.srv1 = {
          hostNames = [
            "srv1"
            "srv1.lab.h4xx.io"
            "10.1.30.12"
          ];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDYyq/6oW5/oNHLk6N3QKiacIPghI+uoUNV5OC2Er4aA";
        };
      }
      (lib.mkIf (builderKeyFile != null) {
        sops.secrets."srv1-builder-key" = {
          sopsFile = builderKeyFile;
          owner = "root";
          format = "binary";
          mode = "0400";
          path = "/var/lib/sops-nix/ssh/srv1-builder-key";
        };

        lukasf.remoteBuilds.sshKeyFile = config.sops.secrets."srv1-builder-key".path;
      })
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
