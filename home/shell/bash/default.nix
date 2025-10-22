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
      # Load private env vars decrypted by SOPS (if present)
      if [ -f "$HOME/.config/secrets/openai.env" ]; then
        set -a
        . "$HOME/.config/secrets/openai.env"
        set +a
      fi
      # Ensure Home-Manager environment variables are loaded for login shells
      if [ -f "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh" ]; then
        source "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh"
      fi
    '';
  };
}
