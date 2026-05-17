{
  config,
  lib,
  pkgs,
  secrets ? { },
  ...
}:

let
  desktopDefaults = config.networking.networkmanager.enable;
  homelabDefaults = config.homelab.personalServer.enable;
  profileCommonRoot = secrets.profileCommon or null;
  srv3BuilderKeyFile =
    if profileCommonRoot != null then "${profileCommonRoot}/ssh/srv3-personal-mgmt.priv" else null;
  hasSrv3BuilderKey = srv3BuilderKeyFile != null && builtins.pathExists srv3BuilderKeyFile;
  nixBuilderHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGciKlKcfvt/Q6IGxJ2MSD80426WIlpGFsJrei+GpBX/ nix-builder-srv3";
  nixBuilderHostKeyB64 = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUdjaUtsS2NmdnQvUTZJR3hKMk1TRDgwNDI2V0lscEdGc0pyZWkrR3BCWC8gbml4LWJ1aWxkZXItc3J2Mwo=";
  testingCachePublicKey = builtins.readFile ../../resources/nix-cache/testing-cache.pub;
in
{
  config = lib.mkMerge [
    {
      lukasf.remoteBuilds.publicHostKey = lib.mkDefault nixBuilderHostKeyB64;
    }
    (lib.mkIf desktopDefaults {
      sops.age.keyFile = lib.mkDefault "/home/lukasf/.config/sops/age/keys.txt";
    })
    (lib.mkIf (desktopDefaults && hasSrv3BuilderKey) {
      sops.secrets."srv3-builder-key" = {
        sopsFile = srv3BuilderKeyFile;
        owner = "root";
        format = "binary";
        mode = "0400";
        path = "/var/lib/sops-nix/ssh/srv3-builder-key";
      };

      lukasf.remoteBuilds = {
        # Use WG-reachable lab DNS directly; the public testing hostname is Cloudflare-proxied.
        hostName = lib.mkDefault "srv3.lab.h4xx.io";
        sshUser = lib.mkDefault "nixbuilder";
        sshKeyFile = lib.mkDefault config.sops.secrets."srv3-builder-key".path;
        publicHostKey = lib.mkForce nixBuilderHostKeyB64;
        connectTimeout = lib.mkDefault 3;
        maxJobs = lib.mkDefault 2;
      };

      lukasf.nixCache = {
        enable = lib.mkDefault true;
        serve = lib.mkDefault false;
        configureClient = lib.mkDefault true;
        cacheHost = lib.mkDefault "nix-testing.h4xx.io";
        cacheUrl = lib.mkDefault "https://nix-testing.h4xx.io";
        publicKey = lib.mkDefault testingCachePublicKey;
        connectTimeout = lib.mkDefault 2;
        fallbackToOfficial = lib.mkDefault true;
      };

      nix.settings.fallback = lib.mkDefault true;

      shared.ssh.knownHosts.nix-builder = {
        hostNames = [
          "srv3.lab.h4xx.io"
          "nix-builder-testing.h4xx.io"
        ];
        publicKey = nixBuilderHostKey;
      };
    })
    (lib.mkIf homelabDefaults {
      sops.age.keyFile = lib.mkDefault "/var/lib/sops-nix/age/keys.txt";
    })
    (lib.mkIf desktopDefaults {
      shared.network.resolved = {
        enable = lib.mkDefault true;
        dnssec = lib.mkDefault "false";
        fallbackDns = lib.mkDefault [
          "1.1.1.1"
        ];
        networkmanagerDns = lib.mkDefault "systemd-resolved";
        resolvconfEnable = lib.mkDefault false;
      };

      services.journald.extraConfig = lib.mkDefault ''
        SystemMaxUse=100M
        RuntimeMaxUse=50M
        RuntimeKeepFree=100M
        SystemMaxFileSize=10M
      '';

      environment.systemPackages = with pkgs; [
        smartmontools
      ];
    })
  ];
}
