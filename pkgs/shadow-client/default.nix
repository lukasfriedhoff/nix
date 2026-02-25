{
  alsa-lib,
  atk,
  at-spi2-atk,
  at-spi2-core,
  autoPatchelfHook,
  cairo,
  cups,
  dbus,
  dpkg,
  expat,
  fetchurl,
  glib,
  gtk3,
  lib,
  libdrm,
  libva,
  libvdpau,
  libxcb,
  libxkbcommon,
  makeWrapper,
  mesa,
  nspr,
  nss,
  pango,
  stdenv,
  xorg,
}:

stdenv.mkDerivation rec {
  pname = "shadow-client";
  version = "9.9.10355";

  src = fetchurl {
    url = "http://repository.shadow.tech/prod/pool/main/s/shadow-prod/shadow-amd64.deb";
    sha256 = "50458e3292ce9bb56b8de6575a05cc1c624c4016212c9a794daca5042e234696";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
  ];

  buildInputs = [
    alsa-lib
    atk
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libva
    libvdpau
    libxcb
    libxkbcommon
    mesa
    nspr
    nss
    pango
    xorg.libX11
    xorg.libXcomposite
    xorg.libXdamage
    xorg.libXext
    xorg.libXfixes
    xorg.libXrandr
  ];

  autoPatchelfIgnoreMissingDeps = true;

  unpackPhase = ''
    dpkg-deb -x $src .
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -R usr/share $out/share
    rm -rf usr

    install -d $out/bin
    makeWrapper $out/share/shadow-prod/shadow-launcher $out/bin/shadow \
      --set-default ELECTRON_DISABLE_SANDBOX 1
    ln -s $out/bin/shadow $out/bin/shadow-prod

    substituteInPlace $out/share/applications/shadow-client-prod.desktop \
      --replace /usr/bin/shadow-prod shadow \
      --replace /usr/share/pixmaps/shadow.png shadow

    install -d $out/share/icons/hicolor/256x256/apps
    cp $out/share/pixmaps/shadow.png $out/share/icons/hicolor/256x256/apps/shadow.png

    runHook postInstall
  '';

  meta = with lib; {
    description = "Shadow PC client for video streaming";
    homepage = "https://shadow.tech";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "shadow";
  };
}
