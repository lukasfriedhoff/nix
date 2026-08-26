{
  config,
  lib,
  pkgs,
  secrets ? { },
  myLib ? import ../../../../lib { inherit lib; },
  ...
}:

let
  cfg = config.homelab.kubernetes;
  inherit (lib)
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    types
    ;

  # open-iscsi drops node parameters between releases: 2.1.12 removed
  # node.session.conn_reopen_log_freq, which 2.1.11 had written into every
  # record under /etc/iscsi/nodes. iscsiadm then rejects the *whole* tree as
  # invalid and exits 7, so Longhorn's engine frontend cannot start and every
  # volume on the node is stuck "attaching" with an empty /dev/longhorn.
  #
  # Only three stale records were enough to take srv9 out entirely. Records are
  # recreated on the next attach, so purging them is safe and self-healing —
  # which matters because every node still on the older open-iscsi will hit
  # this the moment it upgrades.
  purgeIncompatibleIscsiNodes = pkgs.writeShellScript "purge-incompatible-iscsi-nodes" ''
    set -u
    nodes=/etc/iscsi/nodes
    [ -d "$nodes" ] || exit 0

    # A healthy tree (or a genuinely empty one) needs no action. Note that
    # "No records found" is also a non-zero exit, hence matching on the text
    # rather than the status.
    # Deliberately the package this system activates, not an arbitrary one:
    # the records must be judged by the exact iscsiadm that will read them.
    err="$(${config.services.openiscsi.package}/bin/iscsiadm -m node -o show 2>&1 >/dev/null || true)"
    case "$err" in
      *"Unknown parameter name"*)
        echo "iscsid: purging /etc/iscsi/nodes records rejected by this open-iscsi version"
        rm -rf "''${nodes:?}"/* || true
        ;;
    esac
    exit 0
  '';

  isK3s = cfg.distribution == "k3s";
  isRke2 = cfg.distribution == "rke2";
  isServer = cfg.role == "server";
  serviceName = if isK3s then "k3s" else "rke2-${cfg.role}";
  kubeconfig = if isK3s then "/etc/rancher/k3s/k3s.yaml" else "/etc/rancher/rke2/rke2.yaml";

  primaryRoot = secrets.primary or secrets.root or null;
  resolveSecret =
    path:
    myLib.resolveSecretPath {
      root = primaryRoot;
      inherit path;
    };

  gitAuthSecretName = "${cfg.gitops.sourceName}-auth";
  tlsSanFlags = map (san: "--tls-san=${san}") cfg.tlsSans;

  fluxBin = lib.getExe pkgs.fluxcd;
  kubectlBin = lib.getExe pkgs.kubectl;
in
{
  options.homelab.kubernetes = {
    enable = mkEnableOption "Kubernetes node managed by k3s or RKE2";

    distribution = mkOption {
      type = types.enum [
        "k3s"
        "rke2"
      ];
      default = "k3s";
      description = "Kubernetes distribution to run.";
    };

    role = mkOption {
      type = types.enum [
        "server"
        "agent"
      ];
      default = "server";
      description = "Whether this node is a Kubernetes server or agent.";
    };

    serverAddr = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "https://192.168.124.10:9345";
      description = "Registration endpoint used when joining an existing cluster.";
    };

    clusterInit = mkOption {
      type = types.bool;
      default = false;
      description = "Initialize a new HA cluster using the embedded etcd datastore (k3s servers only).";
    };

    embeddedRegistry = mkOption {
      type = types.bool;
      default = false;
      description = "Enable k3s' embedded Spegel registry mirror (P2P image cache between nodes).";
    };

    tokenFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Absolute path to the shared cluster token.";
    };

    nodeName = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Kubernetes node name. Defaults to the NixOS hostname.";
    };

    nodeIP = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "IPv4 or IPv6 address advertised by the node.";
    };

    nodeLabels = mkOption {
      type = types.listOf types.str;
      default = [ ];
      example = [ "h4xx.io/gpu.vendor=virtual" ];
      description = "Labels registered on the Kubernetes node.";
    };

    tlsSans = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional names and addresses included in the API server certificate.";
    };

    extraFlags = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional distribution-specific command-line flags.";
    };

    longhorn.enable = mkEnableOption "Longhorn node prerequisites (open-iscsi + NFS client support)";

    rke2 = {
      cni = mkOption {
        type = types.enum [
          "none"
          "canal"
          "cilium"
          "calico"
          "flannel"
        ];
        default = "canal";
        description = "CNI deployed by RKE2.";
      };

      disable = mkOption {
        type = types.listOf types.str;
        default = [ "rke2-ingress-nginx" ];
        description = "Bundled RKE2 components to disable.";
      };

      cisHardening = mkOption {
        type = types.bool;
        default = false;
        description = "Enable the RKE2 CIS profile and NixOS hardening prerequisites.";
      };
    };

    highAvailability = {
      enable = mkEnableOption "a keepalived registration and API virtual IP";

      virtualIP = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "192.168.124.10";
        description = "Stable registration and Kubernetes API address.";
      };

      virtualIPPrefixLength = mkOption {
        type = types.ints.between 0 128;
        default = 24;
        description = "Network prefix length used when assigning the virtual IP.";
      };

      interface = mkOption {
        type = types.str;
        default = "enp1s0";
        description = "Interface that owns the virtual IP.";
      };

      nodeIPs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Addresses of all keepalived peers, including this node.";
      };

      priority = mkOption {
        type = types.ints.between 1 255;
        default = 100;
        description = "Keepalived election priority for this node.";
      };

      virtualRouterId = mkOption {
        type = types.ints.between 1 255;
        default = 52;
        description = "VRRP router identifier shared by the cluster nodes.";
      };
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

  config = mkIf cfg.enable (mkMerge [
    {
      assertions = [
        {
          assertion = !cfg.gitops.enable || cfg.gitops.repoURL != null;
          message = "homelab.kubernetes.gitops.repoURL must be set when GitOps is enabled.";
        }
        {
          assertion = !cfg.gitops.enable || isServer;
          message = "homelab.kubernetes.gitops can only run on a server node.";
        }
        {
          assertion = cfg.role != "agent" || (cfg.serverAddr != null && cfg.tokenFile != null);
          message = "Kubernetes agents require homelab.kubernetes.serverAddr and tokenFile.";
        }
        {
          assertion = !cfg.clusterInit || (isK3s && isServer);
          message = "homelab.kubernetes.clusterInit is only supported on k3s server nodes.";
        }
        {
          assertion = cfg.serverAddr == null || cfg.tokenFile != null;
          message = "Kubernetes nodes joining through serverAddr require homelab.kubernetes.tokenFile.";
        }
        {
          assertion = cfg.gitops.sshKeyFile == null || cfg.gitops.tokenFile == null;
          message = "Configure only one of homelab.kubernetes.gitops.sshKeyFile or tokenFile.";
        }
        {
          assertion = !cfg.highAvailability.enable || (isRke2 && isServer);
          message = "homelab.kubernetes.highAvailability is supported on RKE2 server nodes.";
        }
        {
          assertion = !cfg.highAvailability.enable || cfg.highAvailability.virtualIP != null;
          message = "homelab.kubernetes.highAvailability.virtualIP must be set.";
        }
        {
          assertion = !cfg.highAvailability.enable || cfg.nodeIP != null;
          message = "homelab.kubernetes.nodeIP must be set when high availability is enabled.";
        }
        {
          assertion =
            !cfg.highAvailability.enable || builtins.elem cfg.highAvailability.virtualIP cfg.tlsSans;
          message = "The high-availability virtual IP must be included in homelab.kubernetes.tlsSans.";
        }
        {
          assertion =
            !cfg.highAvailability.enable
            || (
              builtins.length cfg.highAvailability.nodeIPs >= 2
              && builtins.elem cfg.nodeIP cfg.highAvailability.nodeIPs
            );
          message = "highAvailability.nodeIPs must include this nodeIP and at least one peer.";
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
      swapDevices = lib.mkForce [ ];

      environment.systemPackages =
        with pkgs;
        [
          kubectl
          fluxcd
          git
          cilium-cli
        ]
        ++ lib.optionals cfg.longhorn.enable [
          nfs-utils
        ];

      services.openiscsi = mkIf cfg.longhorn.enable {
        enable = true;
        name = lib.mkDefault "iqn.2026-04.io.h4xx.${config.networking.hostName}:longhorn";
      };
      systemd.sockets.iscsid = mkIf cfg.longhorn.enable {
        enable = lib.mkForce false;
      };
      systemd.services.iscsid = mkIf cfg.longhorn.enable {
        serviceConfig.ExecStartPre = lib.mkBefore [
          "-${pkgs.procps}/bin/pkill -x iscsid"
          "-${purgeIncompatibleIscsiNodes}"
        ];
      };
      boot.supportedFilesystems = lib.optionals cfg.longhorn.enable [
        "nfs"
        "nfs4"
      ];

      systemd.tmpfiles.rules = lib.optionals cfg.longhorn.enable [
        "L+ /bin/mount - - - - /run/wrappers/bin/mount"
        "L+ /usr/bin/mount - - - - /run/wrappers/bin/mount"
        "L+ /usr/bin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
        "L+ /sbin/iscsiadm - - - - /run/current-system/sw/bin/iscsiadm"
        "L+ /sbin/mount.nfs - - - - /run/current-system/sw/bin/mount.nfs"
        "L+ /sbin/mount.nfs4 - - - - /run/current-system/sw/bin/mount.nfs4"
      ];

      networking.firewall = {
        allowedTCPPorts = lib.mkAfter (
          [
            6443
            2379
            2380
            10250
            # node_exporter. The monitoring DaemonSet runs with hostNetwork, so
            # its listener is on the host and the node firewall applies. Without
            # this the pod runs and reports healthy while every scrape fails —
            # srv2 and srv8 served no node metrics at all (no CPU, memory, disk
            # or network) and the node-exporter dashboards covered one node out
            # of three, which is also why disk-pressure alerts only ever fired
            # for the node that happened to be reachable.
            9100
          ]
          ++ lib.optional isRke2 9345
          ++ lib.optional isRke2 2381
        );
        allowedUDPPorts = lib.mkAfter (
          [
            8472
            51820
          ]
          ++ lib.optional isRke2 51821
        );
        checkReversePath = "loose";
      };
    }

    (mkIf isK3s {
      services.k3s = {
        enable = true;
        inherit (cfg) role clusterInit;
        nodeLabel = cfg.nodeLabels;
        # --disable, --write-kubeconfig-mode and --tls-san are server-only
        # k3s flags; agents reject them.
        extraFlags = lib.concatStringsSep " " (
          lib.optionals isServer [
            "--disable traefik"
            "--disable servicelb"
            "--write-kubeconfig-mode 640"
          ]
          ++ lib.optional (isServer && cfg.embeddedRegistry) "--embedded-registry"
          ++ lib.optionals isServer tlsSanFlags
          ++ cfg.extraFlags
        );
      }
      // lib.optionalAttrs (cfg.tokenFile != null) {
        inherit (cfg) tokenFile;
      }
      // lib.optionalAttrs (cfg.nodeName != null) {
        inherit (cfg) nodeName;
      }
      // lib.optionalAttrs (cfg.nodeIP != null) {
        inherit (cfg) nodeIP;
      }
      // lib.optionalAttrs (cfg.serverAddr != null) {
        inherit (cfg) serverAddr;
      };
    })

    (mkIf isRke2 {
      services.rke2 = {
        enable = true;
        inherit (cfg) role;
        nodeLabel = cfg.nodeLabels;
        inherit (cfg.rke2) cisHardening;
        extraFlags = [
          "--write-kubeconfig-mode=0640"
        ]
        ++ tlsSanFlags
        ++ cfg.extraFlags;
      }
      // lib.optionalAttrs (cfg.tokenFile != null) {
        inherit (cfg) tokenFile;
      }
      // lib.optionalAttrs (cfg.nodeName != null) {
        inherit (cfg) nodeName;
      }
      // lib.optionalAttrs (cfg.nodeIP != null) {
        inherit (cfg) nodeIP;
      }
      // lib.optionalAttrs isServer {
        inherit (cfg.rke2) cni disable;
      }
      // lib.optionalAttrs (cfg.serverAddr != null) {
        inherit (cfg) serverAddr;
      };
    })

    (mkIf cfg.highAvailability.enable {
      services.keepalived = {
        enable = true;
        openFirewall = true;
        vrrpScripts.check-rke2 = {
          script = "${pkgs.systemd}/bin/systemctl is-active --quiet rke2-server.service";
          interval = 2;
          timeout = 2;
          rise = 2;
          fall = 2;
          user = "root";
        };
        vrrpInstances.rke2-api = {
          interface = cfg.highAvailability.interface;
          state = "BACKUP";
          inherit (cfg.highAvailability) priority virtualRouterId;
          unicastSrcIp = cfg.nodeIP;
          unicastPeers = builtins.filter (ip: ip != cfg.nodeIP) cfg.highAvailability.nodeIPs;
          virtualIps = [
            {
              addr = "${cfg.highAvailability.virtualIP}/${toString cfg.highAvailability.virtualIPPrefixLength}";
              dev = cfg.highAvailability.interface;
            }
          ];
          trackScripts = [ "check-rke2" ];
        };
      };
    })

    (mkIf cfg.gitops.enable {
      systemd.services.flux-gitops = {
        description = "FluxCD GitOps bootstrap";
        after = [
          "network-online.target"
          "${serviceName}.service"
        ];
        requires = [ "${serviceName}.service" ];
        wants = [ "network-online.target" ];
        environment = {
          KUBECONFIG = kubeconfig;
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "30s";
          ExecStart = pkgs.writeShellScript "flux-gitops-bootstrap" ''
            set -euo pipefail

            api_ready=false
            for ((attempt = 1; attempt <= 120; attempt++)); do
              if [[ -r ${kubeconfig} ]] \
                && ${kubectlBin} --kubeconfig ${kubeconfig} get --raw=/readyz >/dev/null 2>&1; then
                api_ready=true
                break
              fi
              ${pkgs.coreutils}/bin/sleep 5
            done
            if [[ "$api_ready" != true ]]; then
              echo "Kubernetes API did not become ready through ${kubeconfig}" >&2
              exit 1
            fi

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

            ${
              if cfg.gitops.sshKeyFile != null && cfg.gitops.tokenFile == null then
                ''
                  if ! ${fluxBin} --namespace flux-system get sources git ${cfg.gitops.sourceName} >/dev/null 2>&1; then
                    ${fluxBin} create source git ${cfg.gitops.sourceName} \
                      --url=${cfg.gitops.repoURL} \
                      --branch=${cfg.gitops.branch} \
                      --interval=${cfg.gitops.interval} \
                      --private-key-file=${resolveSecret cfg.gitops.sshKeyFile}
                  else
                    ${fluxBin} reconcile source git ${cfg.gitops.sourceName}
                  fi
                ''
              else
                ''
                  ${lib.optionalString (cfg.gitops.tokenFile != null) ''
                    ${kubectlBin} --kubeconfig ${kubeconfig} --namespace flux-system \
                      create secret generic ${gitAuthSecretName} \
                      --from-literal=username=${lib.escapeShellArg cfg.gitops.username} \
                      --from-file=password=${resolveSecret cfg.gitops.tokenFile} \
                      --dry-run=client -o yaml \
                      | ${kubectlBin} --kubeconfig ${kubeconfig} apply -f -
                  ''}

                  ${fluxBin} create source git ${cfg.gitops.sourceName} \
                    --url=${cfg.gitops.repoURL} \
                    --branch=${cfg.gitops.branch} \
                    --interval=${cfg.gitops.interval} \
                    ${lib.optionalString (cfg.gitops.tokenFile != null) "--secret-ref=${gitAuthSecretName}"} \
                    --export \
                    | ${kubectlBin} --kubeconfig ${kubeconfig} apply -f -

                  ${fluxBin} reconcile source git ${cfg.gitops.sourceName}
                ''
            }

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
    })
  ]);
}
