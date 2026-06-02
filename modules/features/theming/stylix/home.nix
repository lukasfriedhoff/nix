{
  pkgs,
  config,
  lib,
  ...
}:
let
  cfg = config.programs.stylix;
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
  options.programs.stylix = {
    enable = lib.mkEnableOption "Stylix theming defaults";
  };

  config = lib.mkMerge [
    {
      programs.stylix.enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      # Stylix/Kvantum sometimes leaves a legacy symlinked Base16Kvantum dir from
      # older generations. HM then tries to back up files inside /nix/store and
      # fails with "Read-only file system". Normalize before link checks.
      home.activation.fixKvantumBase16Symlink = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
        kv_dir="$HOME/.config/Kvantum/Base16Kvantum"
        if [ -L "$kv_dir" ]; then
          target="$(readlink -f "$kv_dir" || true)"
          case "$target" in
            /nix/store/*) rm -f "$kv_dir" ;;
          esac
        fi
      '';

      # Stylix manages the whole Kvantum tree as xdg.configFile."Kvantum".
      # Force replacement to avoid HM backup moves into store-backed paths.
      xdg.configFile."Kvantum".force = true;

      # Adopt new 26.05 default: GTK4 apps use their own theme, not gtk.theme
      gtk.gtk4.theme = null;

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
            applications = 16;
            desktop = 11;
            terminal = 16;
          };
        };
        cursor = {
          package = pkgs.bibata-cursors;
          name = "Bibata-Modern-Ice";
          size = 32;
        };
      };
    })
  ];
}
