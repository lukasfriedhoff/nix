{
  config,
  lib,
  pkgs,
  secrets,
  workSystem ? false,
  ...
}:

let
  cfg = config.programs.git;
  homeDir = config.home.homeDirectory;
  # Work systems get their own path to the second-brain vault: a dedicated
  # Forgejo machine account ("workmac") whose token is a WORK-scoped sops
  # secret, so it decrypts with the key this machine actually has. The
  # personal helper below cannot work here at all - its token lives under
  # profiles/personal, whose age key sops-age deliberately filters out on a
  # work system, and `nix run` in a credential helper hangs without network.
  #
  # Resolved through `secrets`, i.e. the nix-secrets flake input, NOT a
  # ~/git checkout: the work Mac consumes nix-secrets as an input and has no
  # local clone (and workmac deliberately cannot read that repo anyway).
  secondBrainTokenFile = "${secrets.profileShared}/forgejo/second-brain-token.yaml";
  # Credential helpers are also invoked by GUI clients that never source the
  # login shell, so the age key cannot be left to home.sessionVariables.
  ageKeyFile = "${config.xdg.configHome}/sops/age/keys.txt";
in
{
  imports = [
    ./gitignore.nix
  ];
  config = lib.mkMerge [
    {
      programs.git.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      # Keep local workspaces ready; directory creation uses the XDG home to stay portable.
      home.activation.ensureGitDirs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "${homeDir}/git/lukasfriedhoff" "${homeDir}/git/group24" "${homeDir}/git/chaospott"
      '';

      programs.git = {
        lfs.enable = true;

        # # Personal identity (hidden via GitHub noreply)
        # userName  = "lukasfriedhoff";
        # userEmail = "155996615+lukasfriedhoff@users.noreply.github.com";

        signing = {
          # key = "7357275F6DFB9956E72B5BF9F52D0D35FC8BD0DF";
          signByDefault = true;
        };

        # Sensible defaults
        settings = {
          init.defaultBranch = "main";
          pull.ff = "only";
          push.default = "current";
          core.autocrlf = "input";
          user.useConfigOnly = true;
          gpg.format = "openpgp";
          gpg.program = "gpg";

          # Forgejo (git.h4xx.io) is the primary git host; only HTTPS is
          # exposed (SSH 2222 is ClusterIP-only). The helper decrypts the
          # token from nix-secrets via sops at use time - nothing on disk.
          #
          # Personal systems only. On a work system this host-wide section
          # would ALSO match the second-brain URL below (git applies every
          # matching credential section, broadest first), so the personal
          # helper would answer first with a token it cannot decrypt there.
        }
        // lib.optionalAttrs (!workSystem) {
          "credential \"https://git.h4xx.io\"".helper = "${homeDir}/.config/git/forgejo-credential-helper.sh";
        }
        // {

          # Rewrite ANY https://github.com/... to SSH git@github.com:...
          # (works for fetch and push)
          "url \"git@github.com:\"".insteadOf = "https://github.com/";

          # Optional: cover gists too
          "url \"git@gist.github.com:\"".insteadOf = "https://gist.github.com/";
          # Chaospott GitLab: prefer SSH
          "url \"git@git.chaospott.de:\"".insteadOf = "https://git.chaospott.de/";
          # includeIf blocks must use absolute paths + trailing slash
          # See scripts/update-gitignore.sh for refreshing the global ignore list safely.
          "includeIf \"gitdir:${homeDir}/git/lukasfriedhoff/\"" = {
            path = "~/.gitconfig-personal";
          };
          "includeIf \"gitdir:${homeDir}/git/group24/\"" = {
            path = "~/.gitconfig-group24";
          };
          "includeIf \"gitdir:${homeDir}/git/chaospott/\"" = {
            path = "~/.gitconfig-chaospott";
          };
        };
      };

      # Work: credentials ONLY for the vault repo. Git matches credential
      # sections by URL prefix, so this never applies to any other repo on
      # git.h4xx.io - the machine account cannot reach them anyway.
      programs.git.extraConfig = lib.mkIf workSystem {
        "credential \"https://git.h4xx.io/lukasf/second-brain\"".helper =
          "${homeDir}/.config/git/second-brain-credential-helper.sh";
      };

      home.file.".config/git/second-brain-credential-helper.sh" = lib.mkIf workSystem {
        executable = true;
        text = ''
          #!/bin/sh
          # git credential helper for the second-brain vault on a work system.
          # Decrypts a work-scoped token at use time; nothing is written to
          # disk in plaintext. Uses the sops/yq from this profile rather than
          # `nix run`, which needs network and hangs inside a helper.
          [ "$1" = "get" ] || exit 0
          [ -r "${secondBrainTokenFile}" ] || exit 0
          export SOPS_AGE_KEY_FILE="''${SOPS_AGE_KEY_FILE:-${ageKeyFile}}"
          tok=$(${lib.getExe pkgs.sops} -d "${secondBrainTokenFile}" 2>/dev/null \
            | ${lib.getExe pkgs.yq-go} eval '.forgejo.second_brain_token' - 2>/dev/null)
          [ -n "$tok" ] && [ "$tok" != "null" ] || exit 0
          printf 'username=workmac\npassword=%s\n' "$tok"
        '';
      };

      # sops-backed credential helper for the Forgejo primary (declarative
      # copy of the script; no secret material inside). Personal systems
      # only - the ci-token lives under profiles/personal, whose age key is
      # deliberately absent on a work system.
      home.file.".config/git/forgejo-credential-helper.sh" = lib.mkIf (!workSystem) {
        executable = true;
        text = ''
          #!/bin/sh
          # git credential helper for git.h4xx.io (Forgejo primary).
          # Decrypts the token from nix-secrets via sops at use time.
          [ "$1" = "get" ] || exit 0
          tok=$(nix run nixpkgs#sops -- -d "$HOME/git/lukasfriedhoff/nix-secrets/secrets/profiles/personal/shared/forgejo/ci-token.yaml" 2>/dev/null \
            | nix run nixpkgs#yq-go -- eval '.forgejo.ci_token' -)
          # Stay silent rather than handing git an empty password: a blank
          # credential is cached as a failed attempt and stops git from
          # consulting any more specific helper.
          [ -n "$tok" ] && [ "$tok" != "null" ] || exit 0
          printf 'username=lukasf\npassword=%s\n' "$tok"
        '';
      };

      # personal per-path config
      home.file.".gitconfig-personal".text = ''
        [user]
          name = lukasfriedhoff
          email = 155996615+lukasfriedhoff@users.noreply.github.com
          signingkey = 7357275F6DFB9956E72B5BF9F52D0D35FC8BD0DF
        [commit]
          gpgSign = true
        [gpg]
          program = gpg
        [core]
          hooksPath = .githooks
      '';

      # org per-path config
      # TODO(group24): generate a work GPG key, add its fingerprint as
      # signingkey and flip gpgSign to true.
      home.file.".gitconfig-group24".text = ''
        [user]
          name  = Lukas Friedhoff
          email = l.friedhoff@group24.de
        [commit]
          gpgSign = false
        [gpg]
          program = gpg
        [core]
          hooksPath = .githooks
      '';

      # chaospott per-path config
      home.file.".gitconfig-chaospott".text = ''
        [user]
          name = lukasfriedhoff
          email = 155996615+lukasfriedhoff@users.noreply.github.com
          signingkey = 7357275F6DFB9956E72B5BF9F52D0D35FC8BD0DF
        [commit]
          gpgSign = true
        [gpg]
          program = gpg
      '';
    })
  ];
}
