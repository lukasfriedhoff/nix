{ pkgs, ... }:
{
  programs.vscode = {
    enable = true;
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
        "window.zoomLevel" = 2;
        "terminal.integrated.profiles.linux" = {
          Codex = {
            path = "bash";
            args = [ "-lc" "codex" ];
            icon = "sparkle";
          };
        };
        "terminal.integrated.profiles.osx" = {
          Codex = {
            path = "bash";
            args = [ "-lc" "codex" ];
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
}
