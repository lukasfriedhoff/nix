{ config, pkgs, ... }:
let
  jdk = pkgs.temurin-bin-17;
  jdkHome = "${jdk}/lib/openjdk";
in
{
  imports = [
    ./alias-completions.nix
  ];
  programs.bash = {
    enable = true;
    enableCompletion = true;
    # TODO add your custom bashrc here
    bashrcExtra = ''
      # Ensure JDK bin is always first in PATH, even on macOS
      if [ -d "${jdkHome}/bin" ] && [[ ":$PATH:" != *":${jdkHome}/bin:"* ]]; then
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
