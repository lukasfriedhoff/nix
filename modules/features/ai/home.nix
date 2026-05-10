# AI Assistants Configuration
# Manages agents and skills for Claude Code and OpenCode
{
  config,
  lib,
  pkgs,
  profile ? null,
  ...
}:

let
  cfg = config.ai;

  # Auto-enable for desktop profiles
  personalDesktopProfiles = [
    "srv4"
    "tux"
    "tab"
    "lenovo"
  ];
  isPersonalDesktop = profile != null && lib.elem profile personalDesktopProfiles;
  isLinuxDesktop = isPersonalDesktop && (!pkgs.stdenv.isDarwin);
in
{
  imports = [
    # Agents
    ./agents/nix-docs/home.nix
    ./agents/kubernetes-docs/home.nix
    ./agents/home-manager-docs/home.nix

    # Skills
    ./skills/cert-manager/home.nix
    ./skills/cilium/home.nix
    ./skills/flake/home.nix
    ./skills/flux/home.nix
    ./skills/git-master/home.nix
    ./skills/helm/home.nix
    ./skills/home-manager/home.nix
    ./skills/kubernetes/home.nix
    ./skills/kustomize/home.nix
    ./skills/neovim-config/home.nix
    ./skills/nix/home.nix
    ./skills/podman/home.nix
    ./skills/sops-secrets/home.nix
    ./skills/ssh/home.nix
    ./skills/systemd/home.nix
    ./skills/wireguard/home.nix
  ];

  options.ai = {
    enable = lib.mkEnableOption "AI assistants configuration (Claude, OpenCode)";

    enableAllAgents = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable all available agents by default.";
    };

    enableAllSkills = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable all available skills by default.";
    };
  };

  config = lib.mkMerge [
    # Auto-enable for Linux desktop profiles
    (lib.mkIf isLinuxDesktop {
      ai.enable = lib.mkDefault true;
    })

    # When enabled, auto-enable all agents and skills
    (lib.mkIf cfg.enable {
      # Auto-enable all agents when enableAllAgents is true
      ai.agents = {
        nixDocs.enable = lib.mkDefault cfg.enableAllAgents;
        kubernetesDocs.enable = lib.mkDefault cfg.enableAllAgents;
        homeManagerDocs.enable = lib.mkDefault cfg.enableAllAgents;
      };

      # Auto-enable all skills when enableAllSkills is true
      ai.skills = {
        certManager.enable = lib.mkDefault cfg.enableAllSkills;
        cilium.enable = lib.mkDefault cfg.enableAllSkills;
        flake.enable = lib.mkDefault cfg.enableAllSkills;
        flux.enable = lib.mkDefault cfg.enableAllSkills;
        gitMaster.enable = lib.mkDefault cfg.enableAllSkills;
        helm.enable = lib.mkDefault cfg.enableAllSkills;
        homeManager.enable = lib.mkDefault cfg.enableAllSkills;
        kubernetes.enable = lib.mkDefault cfg.enableAllSkills;
        kustomize.enable = lib.mkDefault cfg.enableAllSkills;
        neovimConfig.enable = lib.mkDefault cfg.enableAllSkills;
        nix.enable = lib.mkDefault cfg.enableAllSkills;
        podman.enable = lib.mkDefault cfg.enableAllSkills;
        sopsSecrets.enable = lib.mkDefault cfg.enableAllSkills;
        ssh.enable = lib.mkDefault cfg.enableAllSkills;
        systemd.enable = lib.mkDefault cfg.enableAllSkills;
        wireguard.enable = lib.mkDefault cfg.enableAllSkills;
      };
    })
  ];
}
