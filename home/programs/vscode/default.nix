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
        ]
      );

      userSettings = {
        "editor.formatOnSave" = true;
        "workbench.colorTheme" = "Default Dark Modern";
        "editor.tabSize" = 2;
        "files.trimTrailingWhitespace" = true;
        "window.zoomLevel" = 2;
      };
    };
  };
}
