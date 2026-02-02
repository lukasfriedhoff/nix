{
  pkgs,
  lib,
  config,
  ...
}:

{
  home.packages = lib.mkAfter [
    pkgs.podman
    pkgs.btop
  ];

  programs.oh-my-opencode = {
    enable = true;
    subscriptions = {
      claude = "yes";
      openai = "yes";
      gemini = "no";
      copilot = "yes";
      opencodeZen = "no";
      zaiCodingPlan = "no";
    };
  };

  # Remove old OpenAI API key file; prefer ChatGPT Plus, Gemini Pro, and Copilot sign-ins.
  home.activation.decryptOpenAIEnv = lib.mkForce (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      rm -f "${config.xdg.configHome}/secrets/openai.env"
    ''
  );

  programs.icarusModManager = {
    enable = true;
    autoInstallDotnet80 = true;
  };

  dconf.settings."org/gnome/desktop/wm/keybindings" = {
    "switch-windows" = [ "<Alt>Tab" ];
    "switch-windows-backward" = [ "<Shift><Alt>Tab" ];
    "switch-applications" = [ ];
    "switch-applications-backward" = [ ];
  };
}
