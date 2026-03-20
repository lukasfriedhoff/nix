{
  config,
  lib,
  pkgs,
  secrets ? { },
  ...
}:

let
  cfg = config.homelab.kubernetes;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
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
      throw "homelab.kubernetes.gitops: relative secret path '${file}' requires secrets.primary/root";

  kubeconfig = "/etc/rancher/k3s/k3s.yaml";

  fluxBin = lib.getExe pkgs.fluxcd;
  kubectlBin = lib.getExe pkgs.kubectl;
in
{
  options.homelab.kubernetes = {
    enable = mkEnableOption "single-node Kubernetes (k3s) control plane";

    extraK3sFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional flags passed to k3s via --flag format.";
    };

    gitops = {
      enable = mkEnableOption "FluxCD GitOps bootstrap";
      repoURL = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "ssh://git@github.com/lukasfriedhoff/gitops.git";
        description = "Git repository URL containing Flux manifests.";
      };
      branch = mkOption {
        type = types.str;
        default = "main";
        description = "Git branch Flux should track.";
      };
      path = mkOption {
        type = types.str;
        default = "./clusters/<cluster-name>";
        description = "Kustomization path within the GitOps repository.";
      };
      interval = mkOption {
        type = types.str;
        default = "1m";
        description = "Flux reconciliation interval (e.g. 1m, 5m).";
      };
      sshKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path (absolute or relative to secrets.primary) to the Flux SSH deploy key.";
      };
      tokenFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to a file containing GitHub PAT for HTTPS authentication.";
      };
      sopsAgeKeyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Path to an Age private key file used to create/update flux-system/sops-age.";
      };
      username = mkOption {
        type = types.str;
        default = "git";
        description = "Username for HTTPS authentication (typically GitHub username or 'git').";
      };
      sourceName = mkOption {
        type = types.str;
        default = "gitops";
        description = "Flux GitRepository name.";
      };
      kustomizationName = mkOption {
        type = types.str;
        default = "gitops";
        description = "Flux Kustomization name.";
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = lib.mkIf (cfg.gitops.enable or false) [
      {
        assertion = cfg.gitops.repoURL != null;
        message = "homelab.kubernetes.gitops.repoURL must be set when GitOps is enabled.";
      }
    ];

    boot.kernelModules = [
      "br_netfilter"
      "rbd"
      "nbd"
    ];
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = 1;
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
    };

    environment.systemPackages = with pkgs; [
      kubectl
      fluxcd
      git
      cilium-cli
    ];

    services.k3s = {
      enable = true;
      role = "server";
      extraFlags = lib.concatStringsSep " " (
        [
          "--disable traefik"
          "--disable servicelb"
          "--write-kubeconfig-mode 640"
        ]
        ++ cfg.extraK3sFlags
      );
    };

    networking.firewall = {
      allowedTCPPorts = lib.mkAfter [
        6443
        2379
        2380
        10250
      ];
      allowedUDPPorts = lib.mkAfter [
        8472
        51820
      ];
      checkReversePath = "loose";
    };

    # GitOps bootstrap
    systemd.services.flux-gitops = mkIf cfg.gitops.enable {
      description = "FluxCD GitOps bootstrap";
      after = [ "k3s.service" ];
      requires = [ "k3s.service" ];
      environment = {
        KUBECONFIG = kubeconfig;
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "flux-gitops-bootstrap" ''
          set -euo pipefail

          if ! ${kubectlBin} --kubeconfig ${kubeconfig} get namespace flux-system >/dev/null 2>&1; then
            ${fluxBin} install --namespace flux-system
          fi

          ${lib.optionalString (cfg.gitops.sopsAgeKeyFile != null) ''
            ${kubectlBin} --kubeconfig ${kubeconfig} --namespace flux-system \
              create secret generic sops-age \
              --from-file=age.agekey=${resolveSecret cfg.gitops.sopsAgeKeyFile} \
              --dry-run=client -o yaml \
              | ${kubectlBin} --kubeconfig ${kubeconfig} apply -f -
          ''}

          if ! ${fluxBin} --namespace flux-system get sources git ${cfg.gitops.sourceName} >/dev/null 2>&1; then
            ${fluxBin} create source git ${cfg.gitops.sourceName} \
              --url=${cfg.gitops.repoURL} \
              --branch=${cfg.gitops.branch} \
              --interval=${cfg.gitops.interval} \
              ${
                lib.optionalString (
                  cfg.gitops.sshKeyFile != null
                ) "--private-key-file=${resolveSecret cfg.gitops.sshKeyFile}"
              } \
              ${lib.optionalString (
                cfg.gitops.tokenFile != null
              ) "--username=${cfg.gitops.username} --password=$(cat ${resolveSecret cfg.gitops.tokenFile})"}
          else
            ${fluxBin} reconcile source git ${cfg.gitops.sourceName}
          fi

          # Keep the root Kustomization spec in sync with Nix options (path/source/interval).
          ${fluxBin} create kustomization ${cfg.gitops.kustomizationName} \
            --target-namespace flux-system \
            --source=GitRepository/${cfg.gitops.sourceName} \
            --path='${cfg.gitops.path}' \
            --prune=true \
            --interval=${cfg.gitops.interval} \
            --export \
            | ${kubectlBin} --kubeconfig ${kubeconfig} apply -f -

          ${fluxBin} reconcile kustomization ${cfg.gitops.kustomizationName}
        '';
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
