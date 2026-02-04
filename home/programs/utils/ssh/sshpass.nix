{
  config,
  pkgs,
  lib,
  ...
}:

{
  config = lib.mkIf config.programs.ssh.enable {
    home.packages = with pkgs; [
      sshpass
    ];
  };
}
