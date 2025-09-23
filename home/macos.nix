{ config, lib, pkgs, ... }:
{
  home.username = "lukasfriedhoff";
  home.homeDirectory = "/Users/lukasfriedhoff";

  programs.git.enable = true;
  
  home.packages = [ pkgs.age pkgs.sops ];

  # Example SOPS secret materialized to ~/.config/secrets/openai.key
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    # Point to a repo secret file you already track with SOPS
    defaultSopsFile = "${config.home.homeDirectory}/git/lukasfriedhoff/nix/secrets/openai.enc.yaml";
    secrets."openai_api_key".path = ".config/secrets/openai.key";
  };

  # export it for tools that read env vars
  home.sessionVariables.OPENAI_API_KEY =
    lib.mkIf (config.sops.secrets ? "openai_api_key")
      (builtins.readFile "${config.home.homeDirectory}/.config/secrets/openai.key");

  home.stateVersion = "25.05";
}
