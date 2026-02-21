{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.lukasf.nixosUpgradeDiff;
in
{
  options.lukasf.nixosUpgradeDiff = {
    enable = lib.mkEnableOption "show activation diffs with nvd" // {
      default = true;
    };
  };

  config = lib.mkIf cfg.enable {
    # Show diff between current and new system during activation.
    system.activationScripts.nixosUpgradeDiff = {
      supportsDryActivation = true;
      text = ''
        if [ -e /run/current-system ]; then
          echo "--- diff to current-system"
          ${pkgs.nvd}/bin/nvd --nix-bin-dir=${config.nix.package}/bin diff /run/current-system "$systemConfig"
          echo "---"
        fi
      '';
    };
  };
}
