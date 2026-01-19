{
  pkgs,
  config,
  lib,
  ...
}:
let
  # Inline Catppuccin Mocha Base16 scheme to avoid fetching/building external paths during eval.
  theme = {
    scheme = "Catppuccin Mocha";
    author = "Catppuccin";
    base00 = "1e1e2e";
    base01 = "181825";
    base02 = "313244";
    base03 = "45475a";
    base04 = "585b70";
    base05 = "cdd6f4";
    base06 = "f5e0dc";
    base07 = "b4befe";
    base08 = "f38ba8";
    base09 = "fab387";
    base0A = "f9e2af";
    base0B = "a6e3a1";
    base0C = "94e2d5";
    base0D = "89b4fa";
    base0E = "cba6f7";
    base0F = "f2cdcd";
  };
in
{
  stylix = {
    enable = true;
    # Prefetch wallpaper via stylix to keep switches pure. Swap to a local file if you prefer.
    image = pkgs.fetchurl {
      url = "https://wallpapercave.com/wp/wp9218666.jpg";
      sha256 = "sha256-rB3wJm+aF7zWUYQAYouWwikWYHPFZZHeKQXK+wlZqRE=";
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
      fontconfig.enable = false;
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
