{
  config,
  lib,
  pkgs,
  ...
}:

let
  desktopDefaults = config.networking.networkmanager.enable;
  homelabDefaults = config.homelab.personalServer.enable;
in
{
  config = lib.mkMerge [
    {
      lukasf.remoteBuilds.publicHostKey = lib.mkDefault "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSURZeXEvNm9XNS9vTkhMazZOM1FLaWFjSVBnaEkrdW9VTlY1T0MyRXI0YUEgcm9vdEBuaXhvcwo=";
    }
    (lib.mkIf desktopDefaults {
      sops.age.keyFile = lib.mkDefault "/home/lukasf/.config/sops/age/keys.txt";
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
