{ pkgs, lib, ... }:
{
  home.packages =
    lib.mkIf (!pkgs.stdenv.isDarwin) (
      lib.mkAfter (
        with pkgs;
        [
          htop
          intel-gpu-tools
          pavucontrol
          element-desktop
          chromium
        ]
      )
    );

  xdg.desktopEntries."code" = lib.mkIf (!pkgs.stdenv.isDarwin) {
    name = "Visual Studio Code (Intel)";
    exec = "env DRI_PRIME=0 __NV_PRIME_RENDER_OFFLOAD=0 __GLX_VENDOR_LIBRARY_NAME=modesetting code %F";
    icon = "code";
    genericName = "Text Editor";
    categories = [
      "Utility"
      "TextEditor"
      "Development"
      "IDE"
    ];
    terminal = false;
    type = "Application";
    mimeType = [
      "text/plain"
      "inode/directory"
      "application/x-code-workspace"
      "text/x-python"
      "text/x-c++src"
    ];
    startupNotify = true;
    comment = "Code editing. Redefined.";
  };
}
