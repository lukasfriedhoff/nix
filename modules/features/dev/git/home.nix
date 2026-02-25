{
  config,
  lib,
  ...
}:

let
  cfg = config.programs.git;
  homeDir = config.home.homeDirectory;
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
        mkdir -p "${homeDir}/git/lukasfriedhoff" "${homeDir}/git/dacoso-devops" "${homeDir}/git/chaospott"
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
          "includeIf \"gitdir:${homeDir}/git/dacoso-devops/\"" = {
            path = "~/.gitconfig-dacoso-devops";
          };
          "includeIf \"gitdir:${homeDir}/git/chaospott/\"" = {
            path = "~/.gitconfig-chaospott";
          };
          "includeIf \"gitdir:${homeDir}/git/lukasfriedhoff/nix/\"" = {
            path = "~/.gitconfig-nix-hooks";
          };
        };
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
      '';

      # org per-path config (fill in your org key fingerprint)
      home.file.".gitconfig-dacoso-devops".text = ''
        [user]
          name  = Lukas Friedhoff
          email = lukas.friedhoff@dacoso.com
          signingkey = 22C3C5DEAA39D79FB12328CFE43A3F179FCDD279
        [commit]
          gpgSign = true
        [gpg]
          program = gpg
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

      # Repo-local hooks config: enable .githooks for the nix repo
      home.file.".gitconfig-nix-hooks".text = ''
        [core]
          hooksPath = .githooks
      '';
    })
  ];
}
