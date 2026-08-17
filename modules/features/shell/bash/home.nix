{
  config,
  lib,
  pkgs,
  secrets ? { },
  ...
}:
let
  jdk = pkgs.temurin-bin-17;
  jdkHome = "${jdk}";

  # Remote LUKS unlock helpers. Each host has an `unlock-<host>` SSH alias
  # (resources/ssh/hosts/personal.nix) and a sops-encrypted passphrase at
  # luks/<host>.txt under the profile-shared root of the private
  # nix-secrets repo. Omitted entirely when no profileShared root is set.
  luksUnlockHosts = [
    "srv1"
    "srv2"
    "srv8"
    "srv9"
  ];
  luksSecretsRoot = secrets.profileShared or null;
  luksUnlockFunctions = lib.optionalString (luksSecretsRoot != null) (
    lib.concatMapStrings (host: ''

      # Unlock ${host} LUKS in one go
      unlock-${host}-passphrase() {
        local pass
        pass="$(sops -d "${luksSecretsRoot}/luks/${host}.txt")"
        echo -n "$pass" | ssh unlock-${host} 'umask 077; install -m 600 /dev/stdin /crypt-ramfs/passphrase'
      }
    '') luksUnlockHosts
  );
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
    ''
    + luksUnlockFunctions;

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
