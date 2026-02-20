{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.serverDeployment;
  # Public Git remote used by comin-managed machines.
  repoUrl = "https://github.com/lukasfriedhoff/nix";
  cominDebugScript = pkgs.writeShellScriptBin "comin-debug" ''
    set -euo pipefail
    export PATH="/run/current-system/sw/bin:/run/current-system/sw/sbin"
    service="comin.service"

    if systemctl -q is-active "$service"; then
      echo "warning: $service is running; stop it before using comin-debug" >&2
    fi

    exec_line="$(systemctl show -p ExecStart --value "$service")"
    exec_args="$(printf '%s' "$exec_line" | sed -n 's/.*argv\\[]\\=\\(.*\\) ;.*/\\1/p')"

    if [ -z "$exec_args" ]; then
      echo "error: unable to parse ExecStart argv from $service" >&2
      exit 1
    fi

    comin_bin="$(printf '%s' "$exec_args" | awk '{print $1}')"
    config_path="$(printf '%s' "$exec_args" | awk '{for (i=1;i<=NF;i++) if ($i == \"--config\") {print $(i+1); exit}}')"

    if [ -z "$config_path" ]; then
      echo "error: unable to find --config in ExecStart for $service" >&2
      exit 1
    fi

    exec systemd-run --unit comin-debug --collect \
      --property=Environment=PATH=/run/current-system/sw/bin:/run/current-system/sw/sbin \
      "$comin_bin" --debug run --config "$config_path"
  '';
in
{
  options.lukasf.serverDeployment = {
    enable = lib.mkEnableOption "server deployment defaults via comin";

    enableComin = lib.mkEnableOption "comin-based deployment for ${repoUrl}" // {
      default = true;
    };
  };

  config = lib.mkIf (cfg.enable && cfg.enableComin) {
    services.comin = {
      enable = true;
      hostname = lib.mkDefault config.networking.hostName;
      repositorySubdir = ".";
      remotes = [
        {
          name = "origin";
          url = repoUrl;
          branches.main.name = "develop";
          branches.testing.name = "testing-${config.services.comin.hostname}";
        }
      ];
    };

    environment.systemPackages = [
      cominDebugScript
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/comin 0755 root root -"
    ];
  };
}
