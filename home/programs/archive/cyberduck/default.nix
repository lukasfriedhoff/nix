{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Core kubectl & CLI tools
  home.packages = with pkgs; [
    cyberduck
  ];
}
