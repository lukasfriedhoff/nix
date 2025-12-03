{
  pkgs,
  lib,
  config,
  ...
}:
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
          virt-manager
        ]
      )
    );

  home.file.".ssh/config.d/chaospott" = lib.mkIf (!pkgs.stdenv.isDarwin) {
    source = ../../../resources/ssh/config.d/chaospott;
  };

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

  home.sessionVariables = lib.mkIf (!pkgs.stdenv.isDarwin) {
    SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/ssh-agent.socket";
  };

  systemd.user.services."openssh-agent" = lib.mkIf (!pkgs.stdenv.isDarwin) {
    Unit = {
      Description = "User OpenSSH agent (overrides gcr)";
      PartOf = [ "default.target" ];
    };
    Service = {
      ExecStart = "${pkgs.openssh}/bin/ssh-agent -D -a %t/ssh-agent.socket";
      Restart = "on-failure";
      Environment = "SSH_AUTH_SOCK=%t/ssh-agent.socket";
    };
    Install = {
      WantedBy = [ "default.target" ];
    };
  };

  # Ensure user systemd dirs are executable so Home Manager can place wants symlinks
  home.activation.fixSystemdUserDirs = lib.mkIf (!pkgs.stdenv.isDarwin) (lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    mkdir -p "${config.xdg.configHome}/systemd/user/default.target.wants"
    chmod 755 "${config.xdg.configHome}/systemd"
    chmod 755 "${config.xdg.configHome}/systemd/user"
    chmod 700 "${config.xdg.configHome}/systemd/user/default.target.wants"
  '');

  fonts.fontconfig.enable = lib.mkForce false;
}
