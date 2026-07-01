{ config, pkgs, ... }:
let
  jdk = pkgs.temurin-bin-17;
  jdkHome = "${jdk}";
in
{
  imports = [
    ./alias-completions.nix
  ];
  home.sessionPath = [
    "${jdkHome}/bin"
  ];
  programs.bash = {
    enable = true;
    enableCompletion = true;
    # TODO add your custom bashrc here
    bashrcExtra = ''
      # macOS ships Bash 3.2 which is too old for modern `bash-completion`.
      # Re-exec into Nix Bash for interactive shells so completions work.
      if [[ $- == *i* ]] && (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2) )); then
        exec "${pkgs.bashInteractive}/bin/bash"
      fi

      # Ensure JDK bin is always first in PATH, even on macOS
      if [ -d "${jdkHome}/bin" ]; then
        export PATH="${jdkHome}/bin:$PATH"
      fi
      export JAVA_HOME="${jdkHome}"

      # Load user binaries
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"

      # Source decrypted OpenAI secrets if available so Codex/Neovim inherit them
      codex_secret="$HOME/.config/secrets/openai.env"
      if [ -f "$codex_secret" ]; then
        set -a
        . "$codex_secret"
        set +a
      fi

      # Unlock srv1 LUKS in one go
      unlock-srv1-passphrase() {
        local pass
        pass="$(sops -d "$HOME/git/lukasfriedhoff/nix/secrets/profiles/personal/shared/luks/srv1.txt")"
        echo -n "$pass" | ssh unlock-srv1 'umask 077; install -m 600 /dev/stdin /crypt-ramfs/passphrase'
      }

      # Unlock srv2 LUKS in one go
      unlock-srv2-passphrase() {
        local pass
        pass="$(sops -d "$HOME/git/lukasfriedhoff/nix/secrets/profiles/personal/shared/luks/srv2.txt")"
        echo -n "$pass" | ssh unlock-srv2 'umask 077; install -m 600 /dev/stdin /crypt-ramfs/passphrase'
      }
    '';

    # set some aliases, feel free to add more or remove some
    shellAliases = {
      k = "kubectl";
      tf = "terraform";
      dc = "docker compose";
      urldecode = "python3 -c 'import sys, urllib.parse as ul; print(ul.unquote_plus(sys.stdin.read()))'";
      urlencode = "python3 -c 'import sys, urllib.parse as ul; print(ul.quote_plus(sys.stdin.read()))'";
    };
    initExtra = ''
      # Ensure Home-Manager environment variables are loaded for login shells
      if [ -f "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh" ]; then
        source "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
      fi
    '';
  };
}
