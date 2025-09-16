{ config, pkgs, ... }:

{
  programs.bash = {
    enable = true;
    enableCompletion = true;
    # TODO add your custom bashrc here
    bashrcExtra = ''
      export PATH="$PATH:$HOME/bin:$HOME/.local/bin:$HOME/go/bin"
    '';

    # set some aliases, feel free to add more or remove some
    shellAliases = {
      k = "kubectl";
      tf = "terraform";
      dc = "docker-compose";
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
    '';
  };
}