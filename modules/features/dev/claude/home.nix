{
  lib,
  ...
}:

{
  config = {
    programs."claude-code".enable = lib.mkDefault true;
  };
}
