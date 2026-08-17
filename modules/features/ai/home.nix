# AI Assistants Configuration
# Manages agents and skills for Claude Code and OpenCode
#
# Skills and agents are discovered from the ./skills and ./agents directory
# trees: every subdirectory becomes an option (ai.skills.<dir>.enable /
# ai.agents.<dir>.enable) and, when enabled, is linked into both the Claude
# (~/.claude) and OpenCode (~/.opencode) trees. Adding a new skill is just
# adding a directory with a SKILL.md; agents ship a <dir>.md instead.
{
  config,
  lib,
  pkgs,
  inputs ? null,
  ...
}:

let
  cfg = config.ai;

  dirNamesIn =
    path: lib.attrNames (lib.filterAttrs (_name: type: type == "directory") (builtins.readDir path));

  skillNames = dirNamesIn ./skills;
  agentNames = dirNamesIn ./agents;

  # Skills vendored from upstream repos (flake inputs, see flake.nix).
  # Linked as whole directories because they ship reference files
  # (schemas, sub-guides) alongside SKILL.md.
  externalSkillSources = lib.optionalAttrs (inputs != null) {
    # Official FluxCD skills (Apache-2.0) — schema-grounded; the in-house
    # `flux` skill remains available but these track Flux releases.
    gitops-knowledge = "${inputs.flux-agent-skills}/skills/gitops-knowledge";
    gitops-repo-audit = "${inputs.flux-agent-skills}/skills/gitops-repo-audit";
    gitops-cluster-debug = "${inputs.flux-agent-skills}/skills/gitops-cluster-debug";
    # Official Anthropic skills (Apache-2.0)
    skill-creator = "${inputs.anthropic-skills}/skills/skill-creator";
    mcp-builder = "${inputs.anthropic-skills}/skills/mcp-builder";
    claude-api = "${inputs.anthropic-skills}/skills/claude-api";
    # NixOS management (MIT), regenerated for NixOS 26.05
    nixos-managing = "${inputs.nixos-management-skill}/nixos-managing";
    # Community k8s ecosystem troubleshooting (MIT)
    cert-manager-troubleshooting = "${inputs.community-claude-skills}/cert-manager-troubleshooting";
    external-dns-troubleshooting = "${inputs.community-claude-skills}/external-dns-troubleshooting";
    external-secrets-troubleshooting = "${inputs.community-claude-skills}/external-secrets-troubleshooting";
    kyverno-troubleshooting = "${inputs.community-claude-skills}/kyverno-troubleshooting";
  };
  externalSkillNames = lib.attrNames externalSkillSources;
  allSkillNames = skillNames ++ externalSkillNames;

  # Claude permission allow-list entries contributed by each agent
  # (formerly defined in the per-agent home.nix modules).
  agentAllowLists = {
    nix-docs = [
      "WebFetch(domain:nixos.org)"
      "WebFetch(domain:nix.dev)"
      "WebFetch(domain:wiki.nixos.org)"
      "WebFetch(domain:home-manager-options.extranix.com)"
      "WebFetch(domain:search.nixos.org)"
      "WebFetch(domain:noogle.dev)"
    ];
    kubernetes-docs = [
      "WebFetch(domain:kubernetes.io)"
      "WebFetch(domain:k8s.io)"
      "WebFetch(domain:helm.sh)"
      "WebFetch(domain:fluxcd.io)"
      "WebFetch(domain:docs.cilium.io)"
      "WebFetch(domain:cert-manager.io)"
      "WebFetch(domain:kustomize.io)"
    ];
    home-manager-docs = [
      "WebFetch(domain:home-manager-options.extranix.com)"
      "WebFetch(domain:nix-community.github.io)"
      "WebFetch(domain:github.com)"
    ];
  };
in
{
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

    skills = lib.genAttrs allSkillNames (name: {
      enable = lib.mkEnableOption "${name} skill";
    });

    agents = lib.genAttrs agentNames (name: {
      enable = lib.mkEnableOption "${name} documentation research agent";
    });
  };

  config = lib.mkMerge (
    [
      # Auto-enable for Linux desktop profiles (profiles.desktop.enable is
      # the single source of truth, defined in profile/core/home.nix)
      (lib.mkIf (config.profiles.desktop.enable && !pkgs.stdenv.isDarwin) {
        ai.enable = lib.mkDefault true;
      })

      # When enabled, auto-enable all agents and skills
      (lib.mkIf cfg.enable {
        ai.skills = lib.genAttrs allSkillNames (_name: {
          enable = lib.mkDefault cfg.enableAllSkills;
        });
        ai.agents = lib.genAttrs agentNames (_name: {
          enable = lib.mkDefault cfg.enableAllAgents;
        });
      })
    ]
    # Install each enabled skill for both Claude and OpenCode
    ++ (map (
      name:
      lib.mkIf cfg.skills.${name}.enable {
        home.file.".claude/skills/${name}/SKILL.md".source = ./skills/${name}/SKILL.md;
        home.file.".opencode/skills/${name}/SKILL.md".source = ./skills/${name}/SKILL.md;
      }
    ) skillNames)
    # Vendored external skills: link the whole upstream skill directory
    ++ (map (
      name:
      lib.mkIf cfg.skills.${name}.enable {
        home.file.".claude/skills/${name}".source = externalSkillSources.${name};
        home.file.".opencode/skills/${name}".source = externalSkillSources.${name};
      }
    ) externalSkillNames)
    # Install each enabled agent for both Claude and OpenCode
    ++ (map (
      name:
      lib.mkIf cfg.agents.${name}.enable {
        home.file.".claude/agents/${name}.md".source = ./agents/${name}/${name}.md;
        home.file.".opencode/agents/${name}.md".source = ./agents/${name}/${name}.md;

        lukasf.claude.defaultAllowList = agentAllowLists.${name} or [ ];
      }
    ) agentNames)
  );
}
