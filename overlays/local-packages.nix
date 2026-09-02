_final: prev:

{
  velero_1_9_4 = prev.callPackage ../pkgs/velero_1_9_4 { };
  macmon = prev.callPackage ../pkgs/macmon { };

  # Master PDF Editor pinned to 5.9.60, the newest release the purchased
  # license activates. Consumed by modules/features/profile/desktop/home.nix.
  masterpdfeditorLicenseCompatible = prev.masterpdfeditor.overrideAttrs (_old: {
    version = "5.9.60";
    src = prev.fetchurl {
      url = "https://code-industry.net/public/master-pdf-editor-5.9.60-qt5.x86_64.tar.gz";
      hash = "sha256-KnqqoPhpcQA3mFuuGlZO6RyONgbKFDojDFz+hYFfq9c=";
    };

    installPhase = ''
      runHook preInstall

      substituteInPlace masterpdfeditor5.desktop \
        --replace-fail "Exec=/opt/master-pdf-editor-5/masterpdfeditor5" "Exec=masterpdfeditor5" \
        --replace-fail "Path=/opt/master-pdf-editor-5" "Path=$out/share/masterpdfeditor" \
        --replace-fail "/opt/master-pdf-editor-5/masterpdfeditor5.png" "masterpdfeditor5"

      install -Dm644 masterpdfeditor5.desktop -t $out/share/applications
      install -Dm644 masterpdfeditor5.png -t $out/share/icons/hicolor/128x128/apps
      install -Dm755 masterpdfeditor5 -t $out/share/masterpdfeditor
      cp -r stamps templates lang fonts $out/share/masterpdfeditor

      mkdir -p $out/bin
      ln -s $out/share/masterpdfeditor/masterpdfeditor5 $out/bin/masterpdfeditor5

      runHook postInstall
    '';
  });
}
