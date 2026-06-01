{
  config,
  lib,
  pkgs,
  workSystem ? false,
  ...
}:

let
  cfg = config.programs."microsoft-cli-tools";

  azureCliWithExtensions = pkgs.azure-cli.withExtensions [
    pkgs.azure-cli-extensions."microsoft-fabric"
    pkgs.azure-cli-extensions.powerbidedicated
    pkgs.azure-cli-extensions."stack-hci"
    pkgs.azure-cli-extensions."azure-devops"
  ];

  # PAC CLI 2.x ships as a net10 tool and is currently unreliable with
  # buildDotnetGlobalTool in this pinned nixpkgs; package it directly.
  pac = pkgs.stdenvNoCC.mkDerivation {
    pname = "pac";
    version = "2.7.4";

    src = pkgs.fetchurl {
      url = "https://api.nuget.org/v3-flatcontainer/microsoft.powerapps.cli.tool/2.7.4/microsoft.powerapps.cli.tool.2.7.4.nupkg";
      hash = "sha256-cPl4+MuF+A+8CzJPLR+0c/BZ1xDG/aX4ROHj6kTHRZU=";
    };

    nativeBuildInputs = [
      pkgs.unzip
      pkgs.makeWrapper
    ];

    dontUnpack = true;
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib/pac" "$out/bin"
      unzip -q "$src" "tools/net10.0/any/*" -d "$TMPDIR/pac"
      cp -R "$TMPDIR/pac/tools/net10.0/any/." "$out/lib/pac/"
      ln -sf "${pkgs.dotnetCorePackages.sdk_10_0}/bin/dotnet" "$out/lib/pac/bt-uploader/dotnet"
      makeWrapper "${pkgs.dotnetCorePackages.sdk_10_0}/bin/dotnet" "$out/bin/pac" \
        --set DOTNET_ROOT "${pkgs.dotnetCorePackages.sdk_10_0}/share/dotnet" \
        --add-flags "$out/lib/pac/pac.dll"
      runHook postInstall
    '';

    meta = with lib; {
      description = "Microsoft Power Platform CLI";
      homepage = "https://learn.microsoft.com/power-platform/developer/cli/introduction";
      license = licenses.unfree;
      mainProgram = "pac";
      platforms = platforms.darwin;
    };
  };

  sqlpackage = pkgs.buildDotnetGlobalTool {
    pname = "sqlpackage";
    version = "170.3.93";
    nugetName = "Microsoft.SqlPackage";
    dotnet-sdk = pkgs.dotnetCorePackages.sdk_8_0;
    nugetHash = "sha256-1VcD54B+OsXXaHG+6J23+Wj316fEinQTd6TwqPZqCso=";

    meta = with lib; {
      description = "Microsoft SQL Server DacFx command-line utility";
      homepage = "https://learn.microsoft.com/sql/tools/sqlpackage/sqlpackage";
      license = licenses.unfree;
      mainProgram = "sqlpackage";
      platforms = platforms.darwin;
    };
  };
in
{
  options.programs."microsoft-cli-tools" = {
    enable = lib.mkEnableOption "Microsoft CLI toolchain for Azure/Fabric/Power Platform";
  };

  config = lib.mkMerge [
    {
      programs."microsoft-cli-tools".enable = lib.mkDefault (workSystem && pkgs.stdenv.isDarwin);
    }
    (lib.mkIf cfg.enable {
      home.packages = [
        azureCliWithExtensions
        pkgs.azure-storage-azcopy
        pkgs.azure-functions-core-tools
        pkgs.bicep
        pkgs.kubelogin
        pkgs.powershell
        pac
        sqlpackage
      ];
    })
  ];
}
