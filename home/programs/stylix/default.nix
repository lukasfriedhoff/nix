{
  pkgs,
  config,
  lib,
  ...
}: let
  # Catppuccin Mocha palette shipped with stylix; override if you fancy another theme.
  theme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
in {
  stylix = {
    enable = true;
    # Prefetch wallpaper via stylix to keep switches pure. Swap to a local file if you prefer.
    image = pkgs.fetchurl {
      url = "https://wallpapercave.com/wp/wp9218666.jpg";
      sha256 = "2467657648a269a1bf3aa7be4308642d371bf8cc063a7a1b86731c3d81c9508e";
      curlOptsList = [ "-HUser-Agent: Wget/1.21.4" ];
    };
    base16Scheme = theme;
    polarity = "dark";
    opacity = {
      applications = 0.8;
      terminal = 0.75;
      popups = 0.75;
    };
    targets = {
      # Enable theming for the tools we actively use.
      vscode.enable = true;
      alacritty.enable = true;
    };
    fonts = {
      serif = {
        name = "Cantarell";
        package = pkgs.cantarell-fonts;
      };

      sansSerif = {
        name = "Cantarell";
        package = pkgs.cantarell-fonts;
      };

      monospace = {
        name = "Fira Code";
        package = pkgs.fira-code;
      };

      sizes = {
        applications = 11;
        desktop = 11;
      };
    };
    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
      size = 32;
    };
  };
}
