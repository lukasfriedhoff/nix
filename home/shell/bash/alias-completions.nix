{ config, pkgs, ... }:

let
  # Helper: build bash code to attach completions for all aliases
  mkAliasCompletion = aliases:
    let
      mkComp = name: ''
        if type _${name} &>/dev/null; then
          complete -F _${name} ${name}
        fi
      '';
    in
      builtins.concatStringsSep "\n" (builtins.map mkComp (builtins.attrNames aliases));
in
{
  programs.bash = {
    enable = true;
    enableCompletion = true;

    # This just appends the bash code to .bashrc via Home Manager.
    # It scans all shellAliases, and for each alias, checks for a matching
    # _aliasname completion and attaches it if present.
    initExtra = mkAliasCompletion config.programs.bash.shellAliases;
  };
}