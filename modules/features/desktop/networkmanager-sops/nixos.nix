{
  config,
  lib,
  secrets ? { },
  ...
}:

let
  cfg = config.desktop.networkmanagerSops;

  profileCommonRoot = secrets.profileCommon or null;
  profileSharedRoot = secrets.profileShared or null;

  defaultDir = if profileCommonRoot != null then "${profileCommonRoot}/networkmanager" else null;
  fallbackDir = if profileSharedRoot != null then "${profileSharedRoot}/networkmanager" else null;

  secretsDir =
    if cfg.secretsDir != null then
      if lib.hasPrefix "/" cfg.secretsDir then
        cfg.secretsDir
      else if profileCommonRoot != null then
        "${profileCommonRoot}/${cfg.secretsDir}"
      else if profileSharedRoot != null then
        "${profileSharedRoot}/${cfg.secretsDir}"
      else
        cfg.secretsDir
    else if defaultDir != null && builtins.pathExists defaultDir then
      defaultDir
    else if fallbackDir != null && builtins.pathExists fallbackDir then
      fallbackDir
    else
      null;

  connectionFiles =
    if secretsDir != null && builtins.pathExists secretsDir then
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".txt" name) (
        builtins.readDir secretsDir
      )
    else
      { };

  connectionNames = builtins.attrNames connectionFiles;

  stripTxt = name: lib.removeSuffix ".txt" name;
  nmFileName =
    name:
    let
      base = stripTxt name;
    in
    if lib.hasSuffix ".nmconnection" base then base else "${base}.nmconnection";

  secretAttrName = name: "networkmanager-${lib.replaceStrings [ "." ] [ "-" ] (stripTxt name)}";

  mkSecret = name: {
    name = secretAttrName name;
    value = {
      sopsFile = "${secretsDir}/${name}";
      owner = "root";
      group = "root";
      mode = "0600";
      format = "binary";
      path = "/etc/NetworkManager/system-connections/${nmFileName name}";
      restartUnits = [ "NetworkManager.service" ];
    };
  };
in
{
  options.desktop.networkmanagerSops = {
    enable = lib.mkEnableOption "SOPS-backed NetworkManager connections" // {
      default = true;
    };

    secretsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Directory containing SOPS-encrypted NetworkManager connection files.
        When null, defaults to <secrets.profileCommon>/networkmanager and falls
        back to <secrets.profileShared>/networkmanager if present.
      '';
    };
  };

  config =
    lib.mkIf (cfg.enable && config.networking.networkmanager.enable && connectionNames != [ ])
      {
        sops.secrets = lib.listToAttrs (map mkSecret connectionNames);
      };
}
