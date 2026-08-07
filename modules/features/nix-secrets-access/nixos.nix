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
    enable = lib.mkEnableOption "root SSH access to the private nix-secrets flake input" // {
      default = config.homelab.personalServer.enable or false;
    };

    keyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/nix-secrets/deploy.key";
      description = ''
        Read-only deploy key for the nix-secrets repository.

        Deliberately not a sops secret: this is the credential that fetches the
        secrets, so it cannot itself live inside them. It is bootstrapped out
        of band, the same way the age key is, by
        scripts/servers/deploy-from-iso.sh via nixos-anywhere --extra-files.
      '';
    };

    knownHostsFile = lib.mkOption {
      type = lib.types.str;
      default = "/root/.ssh/known_hosts_github";
      description = "Known-hosts file used for the github.com connection.";
    };
  };

  config = lib.mkIf cfg.enable {
    # nix evaluates as root, so the client config has to be root's rather than
    # the invoking user's. This is the usual failure mode: fetching the input
    # works interactively and then breaks under a root rebuild.
    #
    # comin's auth.access_token_path does not cover this. That authenticates
    # comin's own fetch of the configuration repo; flake inputs are fetched
    # separately by nix and need their own credential.
    programs.ssh.extraConfig = ''
      Match localuser root host github.com
        IdentityFile ${cfg.keyFile}
        IdentitiesOnly yes
        UserKnownHostsFile ${cfg.knownHostsFile}
    '';

    systemd.tmpfiles.rules = [
      "d /var/lib/nix-secrets 0700 root root -"
      "d /root/.ssh 0700 root root -"
    ];

    assertions = [
      {
        assertion = lib.hasPrefix "/" cfg.keyFile;
        message = "lukasf.nixSecretsAccess.keyFile must be an absolute path outside the Nix store.";
      }
    ];
  };
}
