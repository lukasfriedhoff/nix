{
  config,
  lib,
  pkgs,
  secrets ? { },
  ...
}:

let
  cfg = config.homelab.gitops;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    optionalString
    ;

  primaryRoot = secrets.primary or secrets.root or null;
  resolveSecret =
    file:
    if file == null then
      null
    else if lib.hasPrefix "/" file then
      file
    else if primaryRoot != null then
      "${primaryRoot}/${file}"
    else
      throw "homelab.gitops: relative secret '${file}' requires secrets.primary/root";

  workdir = "/var/lib/nixos-gitops";
  sshDir = "/etc/nixos-gitops";
  gitBin = lib.getExe pkgs.git;
  nixosRebuild = lib.getExe pkgs.nixos-rebuild;
in
{
  options.homelab.gitops = {
    enable = mkEnableOption "GitOps-driven nixos-rebuild automation";

    repoURL = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "ssh://git@github.com/lukasfriedhoff/nix.git";
      description = "Git repository containing the flake to deploy.";
    };

    branch = mkOption {
      type = types.str;
      default = "main";
      description = "Git branch to track.";
    };

    flakeAttr = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Flake output (e.g. nixosConfigurations.<name>) to deploy via nixos-rebuild.";
    };

    interval = mkOption {
      type = types.str;
      default = "5m";
      example = "1m";
      description = "Systemd timer OnCalendar/OnUnitActiveSec style interval.";
    };

    sshKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path (absolute or relative) to the deploy SSH private key.";
    };

    extraSwitchFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional flags passed to nixos-rebuild switch.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.repoURL != null;
        message = "homelab.gitops.repoURL must be set when GitOps is enabled.";
      }
    ];

    environment.systemPackages = lib.mkIf (cfg.repoURL != null) [
      pkgs.git
      pkgs.nixos-rebuild
    ];

    systemd.tmpfiles.rules = [
      "d ${workdir} 0750 root root -"
    ]
    ++ lib.optionals (cfg.sshKeyFile != null) [
      "d ${sshDir} 0700 root root -"
    ];

    environment.etc = lib.mkIf (cfg.sshKeyFile != null) {
      "nixos-gitops/id_ed25519" = {
        source = resolveSecret cfg.sshKeyFile;
        mode = "0600";
      };
    };

    systemd.services.nixos-gitops = {
      description = "NixOS GitOps deploy";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = lib.optionalAttrs (cfg.sshKeyFile != null) {
        GIT_SSH_COMMAND = "ssh -i ${sshDir}/id_ed25519 -o StrictHostKeyChecking=no";
      };
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = workdir;
        ExecStart = pkgs.writeShellScript "nixos-gitops-deploy" ''
          set -euo pipefail
          extraFlags="${lib.escapeShellArgs cfg.extraSwitchFlags}"
          repoDir="${workdir}"
          branch=${lib.escapeShellArg cfg.branch}
          repo=${lib.escapeShellArg cfg.repoURL}

          if [ ! -d "$repoDir/.git" ]; then
            ${gitBin} clone --branch "$branch" -- "$repo" "$repoDir"
          else
            ${gitBin} -C "$repoDir" fetch origin
            ${gitBin} -C "$repoDir" checkout "$branch"
            ${gitBin} -C "$repoDir" reset --hard "origin/$branch"
          fi

          ${nixosRebuild} switch --flake "$repoDir#${cfg.flakeAttr}" ''${extraFlags:+$extraFlags}
        '';
      };
    };

    systemd.timers.nixos-gitops = {
      description = "NixOS GitOps deploy timer";
      wants = [ "nixos-gitops.service" ];
      timerConfig = {
        OnBootSec = "2m";
        OnUnitActiveSec = cfg.interval;
        AccuracySec = "30s";
      };
      wantedBy = [ "timers.target" ];
    };
  };
}
