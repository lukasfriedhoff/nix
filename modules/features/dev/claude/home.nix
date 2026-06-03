{
  lib,
  ...
}:

{
  config = {
    programs."claude-code".enable = lib.mkDefault true;
    programs."claude-code".settings = {
      permissions.allow = [
        "Bash(git push *)"
        "Bash(git push)"
      ];
    };
  };
}
