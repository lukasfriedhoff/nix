{ config, pkgs, ... }:
{
  home.file.".bash/alias-completions.sh" = {
    source = ./alias-completions.sh;
    executable = true;
  };

  programs.bash.initExtra = ''
    if [[ -f "$HOME/.bash/alias-completions.sh" ]]; then
      HOME_MANAGER_BASH_COMPLETION_PATH="${pkgs.bash-completion}/etc/profile.d/bash_completion.sh"
      source "$HOME/.bash/alias-completions.sh"
    fi
  '';
}
