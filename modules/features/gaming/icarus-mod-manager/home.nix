{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.icarusModManager;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    optionalString
    ;

  versionUnderscored = lib.replaceStrings [ "." ] [ "_" ] cfg.version;

  sourceUrl =
    if cfg.source != null then
      cfg.source
    else
      "https://github.com/Jimk72/Icarus_Software/raw/main/Icarus_Mod_Manager_${versionUnderscored}.zip";

  dataPackage = pkgs.stdenvNoCC.mkDerivation {
    pname = "icarus-mod-manager-data";
    inherit (cfg) version;
    src = pkgs.fetchzip {
      url = sourceUrl;
      stripRoot = false;
      inherit (cfg) hash;
    };
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/icarus-mod-manager
      cp -R . $out/share/icarus-mod-manager
      runHook postInstall
    '';
  };

  defaultDataDir =
    let
      xdgHome = config.xdg.dataHome or null;
    in
    if xdgHome != null then
      "${xdgHome}/icarus-mod-manager"
    else
      "${config.home.homeDirectory}/.local/share/icarus-mod-manager";

  launcher = pkgs.writeShellApplication {
    name = "icarus-mod-manager";
    runtimeInputs = [
      pkgs.wineWow64Packages.full
      pkgs.coreutils
    ]
    ++ (if cfg.autoInstallDotnet80 then [ pkgs.winetricks ] else [ ]);
    text = ''
      set -euo pipefail
      prefix="${cfg.winePrefix}"
      mutable_dir="${cfg.mutableDataDir}"

      mkdir -p "$mutable_dir"
      if [ ! -e "$mutable_dir/IcarusModManager.exe" ]; then
        echo "Priming writable directory at $mutable_dir..."
        cp -R --no-preserve=mode,ownership "${dataPackage}/share/icarus-mod-manager/." "$mutable_dir/"
      fi

      app_dir="$mutable_dir"

      mkdir -p "$prefix"
      export WINEPREFIX="$prefix"
      export WINEDEBUG=-all

      ${optionalString cfg.autoInstallDotnet80 ''
        if [ ! -f "$prefix/.dotnetdesktop8-installed" ]; then
          echo "Installing .NET Desktop Runtime 8 (dotnetdesktop8) into $prefix (requires network access)..."
          ${pkgs.winetricks}/bin/winetricks -q dotnetdesktop8
          touch "$prefix/.dotnetdesktop8-installed"
        fi
      ''}

      cd "$app_dir"
      exec ${pkgs.wineWow64Packages.full}/bin/wine "$app_dir/IcarusModManager.exe" "$@"
    '';
  };
in
{
  options.programs.icarusModManager = {
    enable = mkEnableOption "Icarus Mod Manager (Wine launcher)";

    version = mkOption {
      type = types.str;
      default = "2.4.0";
      description = "Upstream release version to download.";
    };

    source = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Override URL to the Standalone zip release. Defaults to the official GitHub asset for the configured version.";
    };

    hash = mkOption {
      type = types.str;
      default = "sha256-z4Ns76YtaWgCzUtvddOu7dWJdpCxTpywVoAxLDAynck=";
      description = "Hash of the downloaded archive (SRI format).";
    };

    winePrefix = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.local/share/wineprefixes/icarus-mod-manager";
      description = "Wine prefix used to run Icarus Mod Manager.";
    };

    mutableDataDir = mkOption {
      type = types.str;
      default = defaultDataDir;
      description = "Writable directory where the manager is launched from. The packaged files are copied here on first run.";
    };

    autoInstallDotnet80 = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically install the Windows .NET Desktop Runtime 8 (winetricks dotnetdesktop8) on first launch.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      launcher
      dataPackage
    ];

    xdg.desktopEntries."icarus-mod-manager" = {
      name = "Icarus Mod Manager";
      comment = "Run Icarus Mod Manager via Wine";
      exec = "icarus-mod-manager";
      categories = [
        "Game"
        "Utility"
      ];
      terminal = false;
    };
  };
}
