{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homelab.bootstrapPassword;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.homelab.bootstrapPassword = {
    enable = mkEnableOption "bootstrap password applied from a SOPS secret";

    secretName = mkOption {
      type = types.str;
      default = "bootstrap-password";
      description = "Name of the sops secret holding the bootstrap password.";
    };

    sopsFile = mkOption {
      type = types.nullOr (types.either types.path types.str);
      default = null;
      description = ''
        Encrypted sops file for the bootstrap password. When set, the
        module declares sops.secrets.''${secretName}; when null the host
        is expected to declare the secret itself.
      '';
    };

    users = mkOption {
      type = types.listOf types.str;
      default = [
        "root"
        "nixos"
      ];
      description = "Accounts whose password is set from the secret.";
    };
  };

  config = mkIf cfg.enable {
    sops.secrets = mkIf (cfg.sopsFile != null) {
      ${cfg.secretName} = {
        inherit (cfg) sopsFile;
        format = "binary";
        mode = "0400";
        owner = "root";
      };
    };

    systemd.services.homelab-bootstrap-password = {
      description = "Apply bootstrap password from SOPS secret";
      wantedBy = [ "multi-user.target" ];
      # sops-nix has no sops-install-secrets.service; secrets are placed by the
      # setupSecrets activation script before systemd reaches multi-user.target.
      # Requiring the missing unit made switch-to-configuration fail (status 4).
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -euo pipefail
        secret="${config.sops.secrets.${cfg.secretName}.path}"
        if [ ! -s "$secret" ]; then
          exit 0
        fi

        password="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$secret")"
        if [ -z "$password" ]; then
          echo "bootstrap password secret is empty" >&2
          exit 1
        fi

        ${pkgs.shadow}/bin/chpasswd <<EOF
        ${lib.concatMapStringsSep "\n" (user: "${user}:$password") cfg.users}
        EOF
      '';
    };
  };
}
