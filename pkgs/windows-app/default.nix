# Microsoft Windows App (formerly Remote Desktop) for macOS 14+.
# Not in nixpkgs; packaged from Microsoft's installer .pkg with the version and
# checksum the Homebrew cask pins (https://formulae.brew.sh/api/cask/windows-app.json).
# Only the app bundle is installed; the Microsoft AutoUpdate component is left out.
# Bump: new version, CDN path and sha256 from the cask JSON.
{
  lib,
  stdenvNoCC,
  fetchurl,
  xar,
  cpio,
  pbzx,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "windows-app";
  version = "11.4.4";

  src = fetchurl {
    url = "https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Windows_App_${finalAttrs.version}_installer.pkg";
    sha256 = "70041210ec1c40cbcc1913010fb9a7de7e2b0c8d9f336777775789ae65bc9cab";
  };

  nativeBuildInputs = [
    xar
    cpio
    pbzx
  ];

  # A distribution package: component packages with a Payload archive each
  # (gzip or pbzx compressed cpio).
  unpackPhase = ''
    runHook preUnpack
    mkdir unpacked && cd unpacked
    xar -xf "$src"
    for payload in $(find . -name Payload); do
      ( cd "$(dirname "$payload")" \
        && { gunzip -dc Payload 2>/dev/null || pbzx -n Payload; } | cpio -idm --quiet )
    done
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    app="$(find . -type d -name 'Windows App.app' | head -n1)"
    [ -n "$app" ] || { echo "Windows App.app not found in the package"; find . -maxdepth 3 -type d | head -40; exit 1; }
    mkdir -p "$out/Applications"
    cp -R "$app" "$out/Applications/"
    runHook postInstall
  '';

  meta = {
    description = "Microsoft Windows App (Remote Desktop, Windows 365, Azure Virtual Desktop)";
    homepage = "https://learn.microsoft.com/windows-app/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.platforms.darwin;
  };
})
