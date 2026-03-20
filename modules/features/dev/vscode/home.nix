{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs.vscode;

  # Prefer the packaged Mermaid markdown extension when available.
  mermaidExtension =
    if (pkgs.vscode-extensions ? bierner) && (pkgs.vscode-extensions.bierner ? markdown-mermaid) then
      pkgs.vscode-extensions.bierner.markdown-mermaid
    else if
      (pkgs ? vscode-marketplace)
      && (pkgs.vscode-marketplace ? bierner)
      && (pkgs.vscode-marketplace.bierner ? markdown-mermaid)
    then
      pkgs.vscode-marketplace.bierner.markdown-mermaid
    else
      null;
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
          extensions =
            (with pkgs.vscode-extensions; [
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
            ])
            ++ lib.optional (mermaidExtension != null) mermaidExtension;

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

            # Markdown preview support (including Mermaid rendering).
            "markdown.preview.mermaid" = true;
            "markdown.experimental.previewMermaid" = true;
            "markdown-mermaid.lightModeTheme" = "default";
            "markdown-mermaid.darkModeTheme" = "dark";
            "markdown-mermaid.languages" = [ "mermaid" ];

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
