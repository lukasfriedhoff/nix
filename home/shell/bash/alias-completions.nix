{ config, pkgs, lib, ... }:
let
  # This gets all your shellAliases as an attrset
  aliases = config.programs.bash.shellAliases or {};

  # Generate a bash script that registers completions for each alias
  completionScript =
    let
      mkComp = name: target:
        let
          # base command: first word of the target (e.g., "kubectl" for "kubectl", "docker" for "docker compose")
          baseCmd = builtins.elemAt (lib.strings.splitString " " target) 0;
          compFunc = "_${baseCmd}";
        in ''
          if type ${compFunc} &>/dev/null; then
            complete -o default -F ${compFunc} ${name}
          fi
        '';
      body = lib.concatStringsSep "\n" (
        lib.attrsets.mapAttrsToList mkComp aliases
      );
    in ''
      # Auto-generated Bash completion for all shellAliases
      if [[ ! -v BASH_COMPLETION_VERSINFO ]]; then
        . "${pkgs.bash-completion}/etc/profile.d/bash_completion.sh"
      fi
      ${body}
    '';
in
{
  home.file.".bash/alias-completions.sh".text = completionScript;

  # Ensure it's sourced by bash
  programs.bash.initExtra = ''
    # Auto-completion for aliases
    if [[ -f "$HOME/.bash/alias-completions.sh" ]]; then
      source "$HOME/.bash/alias-completions.sh"
    fi
  '';
}