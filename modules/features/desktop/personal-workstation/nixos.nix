{
  config,
  lib,
  pkgs,
  secrets ? { },
  ...
}:

let
  cfg = config.desktop.personalWorkstation;

  primaryRoot = secrets.primary or secrets.root or null;

  wireguardKeyFile = if primaryRoot != null then "${primaryRoot}/wireguard/homelab.priv" else null;

  hasWireguardKey = wireguardKeyFile != null && builtins.pathExists wireguardKeyFile;
in
{
  options.desktop.personalWorkstation = {
    enable = lib.mkEnableOption "personal desktop workstation app stack";

    wireguardAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "WireGuard homelab address (CIDR) for this workstation.";
    };

  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        desktop.gaming.enable = true;

        lukasf.ollama.enable = lib.mkDefault false;

        lukasf.llamaCpp = {
          enable = true;
          autoStart = false;
        };

        lukasf.openWebui.autoStart = false;

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
          android-tools
          scrcpy
          podman-compose
        ];

        # Allow dynamic binaries from third-party installers (e.g., oh-my-opencode CLI).
        programs.nix-ld = {
          enable = true;
          libraries = with pkgs; [
            stdenv.cc.cc.lib
            glibc
            openssl
            zlib
            icu
            libcxx
          ];
        };

        systemd.tmpfiles.rules = [
          "d /var/lib/sops-nix/ssh 0700 root root -"
        ];
      }
      (lib.mkIf (cfg.wireguardAddress != null && hasWireguardKey) {
        desktop.wireguardHomelab = {
          enable = true;
          address = cfg.wireguardAddress;
        };
      })
    ]
  );
}
