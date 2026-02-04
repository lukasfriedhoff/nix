{
  config,
  lib,
  ...
}:

let
  cfg = config.shared.ssh;
in
{
  options.shared.ssh = {
    knownHosts = lib.mkOption {
      type =
        with lib.types;
        attrsOf (submodule {
          options = {
            hostNames = lib.mkOption {
              type = listOf str;
              description = "Hostnames or IPs for this known host entry.";
            };
            publicKey = lib.mkOption {
              type = str;
              description = "SSH public key for the host.";
            };
          };
        });
      default = { };
      description = "Shared SSH known-hosts entries applied via programs.ssh.knownHosts.";
    };
  };

  config = lib.mkIf (cfg.knownHosts != { }) {
    programs.ssh.knownHosts = cfg.knownHosts;
  };
}
