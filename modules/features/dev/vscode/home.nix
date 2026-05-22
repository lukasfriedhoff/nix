{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs.vscode;

  # Python with Jupyter support for VSCode Jupyter extension
  pythonWithJupyter = pkgs.python3.withPackages (ps: [
    ps.jupyter
    ps.ipykernel
    ps.notebook
  ]);

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

  # Marketplace extensions (MS Fabric, SQL Server, Jupyter)
  marketplaceExtensions =
    if pkgs ? vscode-marketplace then
      with pkgs.vscode-marketplace;
      [
        # MS Fabric extensions
        fabric.vscode-fabric
        # MS SQL Server extensions
        ms-mssql.mssql
        ms-mssql.data-workspace-vscode
        ms-mssql.sql-database-projects-vscode
        ms-mssql.sql-bindings-vscode
        # Jupyter (required by Fabric)
        ms-toolsai.jupyter
        ms-toolsai.jupyter-keymap
        ms-toolsai.jupyter-renderers
        ms-toolsai.vscode-jupyter-cell-tags
        ms-toolsai.vscode-jupyter-slideshow
      ]
    else
      [ ];

  # VSCode settings file path (platform-specific)
  settingsPath =
    if pkgs.stdenv.isDarwin then
      "Library/Application Support/Code/User/settings.json"
    else
      ".config/Code/User/settings.json";

  keybindingsPath =
    if pkgs.stdenv.isDarwin then
      "Library/Application Support/Code/User/keybindings.json"
    else
      ".config/Code/User/keybindings.json";
in
{
  config = lib.mkMerge [
    {
      programs.vscode.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      # Activation script to make VSCode config files mutable
      # This converts symlinks to actual files so extensions can write to them
      home.activation.vscodeSettingsMutable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settingsFile="$HOME/${settingsPath}"
        keybindingsFile="$HOME/${keybindingsPath}"

        # Make settings.json mutable
        if [ -L "$settingsFile" ]; then
          target=$(readlink "$settingsFile")
          if [ -f "$target" ]; then
            rm "$settingsFile"
            cp "$target" "$settingsFile"
            chmod u+w "$settingsFile"
          fi
        fi

        # Make keybindings.json mutable
        if [ -L "$keybindingsFile" ]; then
          target=$(readlink "$keybindingsFile")
          if [ -f "$target" ]; then
            rm "$keybindingsFile"
            cp "$target" "$keybindingsFile"
            chmod u+w "$keybindingsFile"
          fi
        fi
      '';

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
            ++ lib.optional (mermaidExtension != null) mermaidExtension
            ++ marketplaceExtensions;

          userSettings = {
            "editor.formatOnSave" = true;
            "editor.tabSize" = 2;
            "editor.fontSize" = lib.mkForce 14;
            "editor.lineHeight" = lib.mkForce 22;
            "files.trimTrailingWhitespace" = true;
            "files.autoSave" = "afterDelay";
            "files.autoSaveDelay" = 1000;
            "terminal.integrated.fontSize" = lib.mkForce 13;
            "window.zoomLevel" = lib.mkForce 0;
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

            # Python and Jupyter settings (required by MS Fabric extension)
            "python.defaultInterpreterPath" = "${pythonWithJupyter}/bin/python";
            "jupyter.jupyterLaunchTimeout" = 600000;

            # MS Fabric settings - local work folder will be set by the extension
            # after settings.json becomes mutable

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
