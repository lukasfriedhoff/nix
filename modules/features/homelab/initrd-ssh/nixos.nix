{
  config,
  lib,
  ...
}:

let
  cfg = config.homelab.initrdSsh;
in
{
  options.homelab.initrdSsh = {
    enable = lib.mkEnableOption "initrd SSH unlock profile for homelab servers";

    authorizedKeyFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to the public SSH key used for initrd unlock and post-boot access.";
    };

    port = lib.mkOption {
      type = lib.types.ints.u16;
      default = 2222;
      description = "SSH port to expose in initrd for remote unlock.";
    };

    hostKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "/etc/ssh/ssh_host_ed25519_key" ];
      description = "Host keys exposed by the initrd SSH server.";
    };

    authorizedUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "root"
        "nixos"
      ];
      description = "User accounts that should trust the initrd unlock key post-boot.";
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.authorizedKeyFile != null;
            message = "homelab.initrdSsh.authorizedKeyFile must be set when initrd SSH is enabled.";
          }
        ];
      }
      (lib.mkIf (cfg.authorizedKeyFile != null) (
        let
          authorizedKey = builtins.readFile cfg.authorizedKeyFile;
        in
        {
          boot.initrd.network = {
            enable = true;
            ssh = {
              enable = true;
              inherit (cfg) port;
              authorizedKeys = [ authorizedKey ];
              inherit (cfg) hostKeys;
            };
          };

          users.users = lib.genAttrs cfg.authorizedUsers (_: {
            openssh.authorizedKeys.keys = lib.mkAfter [ authorizedKey ];
          });
        }
      ))
    ]
  );
}
