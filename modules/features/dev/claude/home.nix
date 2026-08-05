{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.claude;

  defaultSettings = pkgs.writeText "claude-code-default-settings.json" (
    builtins.toJSON {
      "$schema" = "https://json.schemastore.org/claude-code-settings.json";
      permissions.allow = cfg.defaultAllowList;
    }
  );
in
{
  options.lukasf.claude.defaultAllowList = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Permissions written into settings.json on first activation.";
  };

  config = {
    lukasf.claude.defaultAllowList = [
      "Bash(git push *)"
      "Bash(git push)"
    ];

    programs."claude-code".enable = lib.mkDefault true;

    home.activation.claudeCodeDefaultSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings_file="${config.home.homeDirectory}/.claude/settings.json"
      if [ -L "$settings_file" ]; then
        $DRY_RUN_CMD rm "$settings_file"
      fi
      if [ ! -f "$settings_file" ]; then
        $DRY_RUN_CMD mkdir -p "$(dirname "$settings_file")"
        $DRY_RUN_CMD cp ${defaultSettings} "$settings_file"
        $DRY_RUN_CMD chmod 644 "$settings_file"
      fi
    '';
  };
}
