{
  config,
  lib,
  pkgs,
  ...
}:

let
  defaultSettings = pkgs.writeText "claude-code-default-settings.json" (
    builtins.toJSON {
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
      permissions.allow = [
        "Bash(git push *)"
        "Bash(git push)"
      ];
    }
  );
in
{
  config = {
    programs."claude-code".enable = lib.mkDefault true;

    home.activation.claudeCodeDefaultSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings_file="${config.home.homeDirectory}/.claude/settings.json"
      if [ ! -f "$settings_file" ] || [ -L "$settings_file" ]; then
        $DRY_RUN_CMD mkdir -p "$(dirname "$settings_file")"
        $DRY_RUN_CMD cp ${defaultSettings} "$settings_file"
        $DRY_RUN_CMD chmod 644 "$settings_file"
      fi
    '';
  };
}
