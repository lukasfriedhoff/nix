{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;

    extraPackages = with pkgs; [
      ripgrep fd git lazygit gcc gnumake unzip
      nodejs_22 python3 lua-language-server
      tree-sitter
    ];

    # HM will embed this into the generated config
    extraLuaConfig = builtins.readFile ./nvim/init.lua;
  };

  home.packages = with pkgs; [
    jq
    bash-language-server
    yaml-language-server
  ];
}
