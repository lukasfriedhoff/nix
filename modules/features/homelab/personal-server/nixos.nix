{
  config,
  lib,
  secrets ? { },
  myLib ? import ../../../../lib { inherit lib; },
  ...
}:

let
  cfg = config.homelab.personalServer;

  # Hash of the bootstrap password "ChangeMeNow!".
  defaultPasswordHash = "$6$glGvahkD70PkQnLA$lvYOyuqYSclm5/Y1IY60aeAUp06HVy7qhzTTibwkApJb2pZSZpP0HFWDwaCAqSOmSNljCkpIJ04yLdieM5Gsh1";

  primaryRoot = secrets.primary or secrets.root or null;
  resolveSecret =
    path:
    myLib.resolveSecretPath {
      root = primaryRoot;
      inherit path;
    };
in
{
  options.homelab.personalServer = {
    enable = lib.mkEnableOption "opinionated defaults for personal homelab nodes";

    defaultPasswordHash = lib.mkOption {
      type = lib.types.str;
      default = defaultPasswordHash;
      description = ''
        SHA-512 password hash used for the root and nixos users (defaults to
        "ChangeMeNow!"; change immediately after install).
      '';
    };

    managementPubKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Path to the SSH public key that should be authorised for root/nixos logins.
        Relative paths resolve against <option>secrets.primary</option> or <option>secrets.root</option>.
      '';
    };

    usePasswordAuth = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Allow SSH password authentication during bootstrap (off by default; console-only passwords stay usable).";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.useDHCP = lib.mkDefault true;
    time.timeZone = lib.mkDefault "Europe/Berlin";

    users.mutableUsers = true;

    users.users.root.initialHashedPassword = cfg.defaultPasswordHash;
    users.users.nixos = {
      isNormalUser = true;
      description = "Bootstrap user";
      extraGroups = [ "wheel" ];
      initialHashedPassword = cfg.defaultPasswordHash;
    };

    services.openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "prohibit-password";
        PasswordAuthentication = cfg.usePasswordAuth;
        KbdInteractiveAuthentication = cfg.usePasswordAuth;
      };
      authorizedKeysFiles = lib.mkIf (cfg.managementPubKey != null) (
        lib.mkAfter [ config.sops.secrets."homelab-mgmt-key".path ]
      );
    };

    sops.secrets."homelab-mgmt-key" = lib.mkIf (cfg.managementPubKey != null) {
      sopsFile = resolveSecret cfg.managementPubKey;
      format = "binary";
      mode = "0400";
      owner = "root";
    };

  };
}
