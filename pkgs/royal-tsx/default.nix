# Royal TSX (closed-source macOS remote-management client: RDP, VNC, SSH, ...).
# Not in nixpkgs; packaged from the vendor .dmg with the version and checksum
# the Homebrew cask pins (https://formulae.brew.sh/api/cask/royal-tsx.json).
# Bump: new version + sha256 from the cask JSON.
{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "royal-tsx";
  version = "6.4.5.1000";

  src = fetchurl {
    url = "https://royaltsx-v6.royalapps.com/updates/royaltsx_${finalAttrs.version}.dmg";
    sha256 = "aea06877ff32bba0c9627b162e3bb44473551936708e6a931b95a1ece4127454";
  };

  nativeBuildInputs = [ _7zz ];

  # 7zz reads the APFS image that undmg cannot. -sns- stops it from writing
  # the xattrs as "<file>:com.apple.provenance" side files. The one symlink
  # that points at another symlink is refused by 7zz as "dangerous" (non-zero
  # exit), so it is excluded and recreated by hand; the bundle's code
  # signature seals it, so it cannot just be left out.
  unpackPhase = ''
    runHook preUnpack
    7zz x -snld -sns- '-x!Royal TSX.app/Contents/Libraries/libSystem.Native.dylib' "$src"
    ln -s ../MacOS/libSystem.Native.dylib 'Royal TSX.app/Contents/Libraries/libSystem.Native.dylib'
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications"
    cp -R 'Royal TSX.app' "$out/Applications/"
    runHook postInstall
  '';

  meta = {
    description = "Royal TSX, remote management client (RDP, VNC, SSH, web)";
    homepage = "https://www.royalapps.com/ts/mac";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = lib.platforms.darwin;
  };
})
