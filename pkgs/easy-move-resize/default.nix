# i3/sway-style modifier+drag window move/resize for macOS. Upstream ships a
# signed universal .app zip; no nixpkgs package exists.
{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "easy-move-resize";
  version = "1.8.1";

  src = fetchzip {
    url = "https://github.com/dmarcotte/easy-move-resize/releases/download/${finalAttrs.version}/EasyMoveResize-signed.zip";
    hash = "sha256-u2Uc7yh2gAMK8lAN8s4+gpNMJwwsT77kVm9VlkpDfPU=";
    stripRoot = false;
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/Applications
    cp -R "Easy Move+Resize.app" $out/Applications/
    # unzip materializes AppleDouble sidecars (._*) from the zip; they count
    # as sealed-resource additions and invalidate the code signature, which
    # macOS reports as "app is damaged".
    find $out/Applications -name '._*' -delete
    runHook postInstall
  '';

  meta = {
    description = "Modifier key + mouse drag move/resize for macOS windows (X11 style)";
    homepage = "https://github.com/dmarcotte/easy-move-resize";
    license = lib.licenses.mit;
    platforms = [
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
