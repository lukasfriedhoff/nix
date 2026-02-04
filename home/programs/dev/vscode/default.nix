{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs.vscode;
in
{
  config = lib.mkMerge [
    {
      programs.vscode.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      programs.vscode = {
        package = pkgs.vscode;
        profiles.default = {
          extensions = (
            with pkgs.vscode-extensions;
            [
              golang.go
              hashicorp.hcl
              hashicorp.terraform
              jnoortheen.nix-ide
              redhat.vscode-yaml
              redhat.vscode-xml
              vscjava.vscode-java-pack
              ms-python.python
              ms-kubernetes-tools.vscode-kubernetes-tools
              dbaeumer.vscode-eslint
              github.copilot
              github.copilot-chat
            ]
          );

          userSettings = {
            "editor.formatOnSave" = true;
            "editor.tabSize" = 2;
            "files.trimTrailingWhitespace" = true;
            "files.autoSave" = "afterDelay";
            "files.autoSaveDelay" = 1000;
            "window.zoomLevel" = 2;
            "update.mode" = "none";
            "update.showReleaseNotes" = false;
            "extensions.autoUpdate" = false;
            "extensions.autoCheckUpdates" = false;
            "terminal.integrated.defaultProfile.linux" = "Nix Bash";
            "terminal.integrated.profiles.linux" = {
              "Nix Bash" = {
                path = "${pkgs.bashInteractive}/bin/bash";
                args = [ "-l" ];
              };
              Codex = {
                path = "${pkgs.bashInteractive}/bin/bash";
                args = [
                  "-lc"
                  "codex"
                ];
                icon = "sparkle";
              };
            };
            "terminal.integrated.defaultProfile.osx" = "Nix Bash";
            "terminal.integrated.profiles.osx" = {
              "Nix Bash" = {
                path = "${pkgs.bashInteractive}/bin/bash";
                args = [ "-l" ];
              };
              Codex = {
                path = "${pkgs.bashInteractive}/bin/bash";
                args = [
                  "-lc"
                  "codex"
                ];
                icon = "sparkle";
              };
            };
          };

          keybindings = [
            {
              key = "ctrl+alt+c";
              command = "workbench.action.terminal.newWithProfile";
              args.profileName = "Codex";
              when = "terminalProcessSupported";
            }
          ];
        };
      };
    })
  ];
}
