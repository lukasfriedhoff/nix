{
  config,
  lib,
  ...
}:

let
  cfg = config.lukasf.nixSecretsAccess;
in
{
  options.lukasf.nixSecretsAccess = {
    enable = lib.mkEnableOption "root SSH access to the private nix-secrets flake input";

    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/root/.ssh/nix-secrets-deploy";
      description = ''
        Read-only deploy key for the nix-secrets repository.

        Deliberately not a sops secret: this is the credential that fetches
        the secrets, so it cannot itself live inside them. Install it once,
        out of band:
          sudo mkdir -p /var/root/.ssh && sudo install -m 0600 <key> /var/root/.ssh/nix-secrets-deploy
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # `sudo darwin-rebuild` evaluates as root, and flake inputs are fetched
    # by the evaluating process, so root needs its own credential for the
    # private nix-secrets repo. macOS's stock /etc/ssh/ssh_config includes
    # ssh_config.d, and nix-darwin owns files there via environment.etc.
    environment.etc."ssh/ssh_config.d/100-nix-secrets-access.conf".text = ''
      Match user root host github.com
        IdentityFile ${cfg.keyFile}
        IdentitiesOnly yes
    '';
  };
}
