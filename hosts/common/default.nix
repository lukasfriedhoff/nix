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
  nixBuilderProdHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDUAq2vzYFMRDHO2UVka2fCVXoOwrMWauy6JjlVeIbl5 nix-remote-builder-prod";
  nixBuilderProdHostKeyB64 = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSURVQXEydnpZRk1SREhPMlVWa2EyZkNWWG9Pd3JNV2F1eTZKamxWZUlibDUgbml4LXJlbW90ZS1idWlsZGVyLXByb2Q=";
  nixBuilderTestingHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIUnp+yz5VYFwdQUSlGDI3KfC+7hyGi2KHWRqLfxCCFf nix-builder-testing";
  testingCachePublicKey = lib.removeSuffix "\n" (
    builtins.readFile ../../resources/nix-cache/testing-cache.pub
  );
  atticCachePublicKeyFile = ../../resources/attic-cache/homelab.pub;
  hasAtticCachePublicKey = builtins.pathExists atticCachePublicKeyFile;
  atticCachePublicKey =
    if hasAtticCachePublicKey then
      lib.removeSuffix "\n" (builtins.readFile atticCachePublicKeyFile)
    else
      null;
in
{
  config = lib.mkMerge [
    {
      lukasf.remoteBuilds.publicHostKey = lib.mkDefault nixBuilderProdHostKeyB64;
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
        # Use the production Kubernetes SSH builder through the VPN-only NodePort.
        hostName = lib.mkDefault "nix-builder-prod";
        sshHostName = lib.mkDefault "srv8.lab.h4xx.io";
        sshPort = lib.mkDefault 30610;
        sshUser = lib.mkDefault "root";
        sshKeyFile = lib.mkDefault config.sops.secrets."srv3-builder-key".path;
        publicHostKey = lib.mkForce nixBuilderProdHostKeyB64;
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
          "nix-builder"
          "nix-builder-prod"
          "[srv8.lab.h4xx.io]:30610"
          "[10.1.30.27]:30610"
          "[srv2.lab.h4xx.io]:30610"
          "[10.1.30.26]:30610"
        ];
        publicKey = nixBuilderProdHostKey;
      };

      shared.ssh.knownHosts.nix-builder-testing = {
        hostNames = [
          "nix-builder-testing"
          "[srv3.lab.h4xx.io]:30610"
          "[10.1.20.111]:30610"
        ];
        publicKey = nixBuilderTestingHostKey;
      };
    })
    (lib.mkIf ((desktopDefaults || homelabDefaults) && hasAtticCachePublicKey) {
      lukasf.nixCache.configureClient = lib.mkForce false;

      lukasf.atticCache = lib.mkIf hasAtticCachePublicKey {
        enable = lib.mkDefault true;
        serve = lib.mkDefault false;
        configureClient = lib.mkDefault true;
        serverUrl = lib.mkDefault "https://attic-testing.h4xx.io";
        cacheName = lib.mkDefault "homelab";
        publicKey = lib.mkDefault atticCachePublicKey;
        priority = lib.mkDefault 30;
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
