{ pkgs, lib, ... }:
{
  home.packages = lib.mkIf (!pkgs.stdenv.isDarwin) (
    lib.mkAfter (with pkgs; [
      htop
      intel-gpu-tools
      pavucontrol
      element-desktop
    ])
  );
}
