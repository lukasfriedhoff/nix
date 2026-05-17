{
  alsa-lib,
  atk,
  at-spi2-atk,
  autoPatchelfHook,
  cairo,
  cups,
  curl,
  dbus,
  expat,
  fetchurl,
  gdk-pixbuf,
  gtk3,
  lib,
  libbsd,
  libGL,
  libidn2,
  libinput,
  libkrb5,
  libnghttp2,
  libopus,
  libpsl,
  libpulseaudio,
  libsecret,
  libuuid,
  libva,
  libvdpau,
  libx11,
  libxcb,
  libxcb-image,
  libxcb-render-util,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxfixes,
  libxi,
  libxinerama,
  libxrandr,
  libxscrnsaver,
  libxshmfence,
  libxtst,
  makeWrapper,
  mesa,
  nspr,
  nss,
  openldap,
  openssl,
  pango,
  patchelf,
  pulseaudio,
  rtmpdump,
  stdenv,
  systemd,
  wrapGAppsHook3,
  zlib,
}:

stdenv.mkDerivation rec {
  pname = "shadow-client-appimage";
  version = "9.9.10355.16013";

  src = fetchurl {
    url = "https://update.shadow.tech/launcher/prod/linux/ubuntu_18.04/ShadowPC.AppImage";
    hash = "sha256-4+cvub8BoxPSbpuBJ5YsonXIxPhyqto6BYFvtmbf1cA=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    makeWrapper
    patchelf
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    atk
    at-spi2-atk
    cairo
    cups
    curl
    expat
    gdk-pixbuf
    gtk3
    libbsd
    libidn2
    libinput
    libkrb5
    libnghttp2
    libopus
    libpsl
    libpulseaudio
    libuuid
    libva
    libvdpau
    mesa
    nspr
    nss
    openldap
    openssl
    pango
    rtmpdump
    libx11
    libxcomposite
    libxcursor
    libxdamage
    libxfixes
    libxi
    libxrandr
    libxscrnsaver
    libxtst
    libxinerama
    libxcb
    libxshmfence
    libxcb-image
    libxcb-render-util
    zlib
  ];

  runtimeDependencies = [
    stdenv.cc.cc.lib
    dbus
    libGL
    libsecret
    libva
    pulseaudio
    systemd
    libinput
  ];

  unpackPhase = ''
    cp $src ./Shadow.AppImage
    chmod 777 ./Shadow.AppImage

    patchelf \
      --set-interpreter ${stdenv.cc.bintools.dynamicLinker} \
      --replace-needed libz.so.1 ${zlib}/lib/libz.so.1 \
      ./Shadow.AppImage

    ./Shadow.AppImage --appimage-extract
    rm ./Shadow.AppImage
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/opt
    mkdir -p $out/lib
    mkdir -p $out/bin
    mkdir -p $out/share/applications

    cp -R ./squashfs-root/usr/share/* $out/share/

    ln -s ${lib.getLib systemd}/lib/libudev.so.1 $out/lib/libudev.so.1
    rm -r ./squashfs-root/usr/lib
    rm ./squashfs-root/AppRun
    mv ./squashfs-root $out/opt/shadow-appimage

    displayDir="$out/opt/shadow-appimage/resources/app.asar.unpacked/release/native"
    displayBin="$displayDir/ShadowPCDisplay"
    mv "$displayBin" "$displayBin.bin"
    cat > "$displayBin" <<EOF
    #!${stdenv.shell}
    cd "$displayDir"
    export LD_LIBRARY_PATH="$displayDir:$out/opt/shadow-appimage:$out/lib:${lib.makeLibraryPath runtimeDependencies}:$LD_LIBRARY_PATH"
    exec "$displayBin.bin" --no-usb --agent "Linux;x64;Chrome 80.0.3987.165;latest" "\$@"
    EOF
    chmod +x "$displayBin"

    cat > $out/bin/shadow <<EOF
    #!${stdenv.shell}
    export LD_LIBRARY_PATH="$out/opt/shadow-appimage:$out/lib:${lib.makeLibraryPath runtimeDependencies}:$LD_LIBRARY_PATH"
    if [ -x /run/wrappers/bin/chrome-sandbox ]; then
      export CHROME_DEVEL_SANDBOX=/run/wrappers/bin/chrome-sandbox
      export ELECTRON_DISABLE_SANDBOX=0
    elif [ -x /run/wrappers/bin/shadow-chrome-sandbox ]; then
      export CHROME_DEVEL_SANDBOX=/run/wrappers/bin/shadow-chrome-sandbox
      export ELECTRON_DISABLE_SANDBOX=0
    else
      export ELECTRON_DISABLE_SANDBOX=''${ELECTRON_DISABLE_SANDBOX:-1}
    fi
    exec "$out/opt/shadow-appimage/shadow-launcher" "\$@"
    EOF
    chmod +x $out/bin/shadow

    substitute $out/opt/shadow-appimage/shadow-launcher.desktop \
      $out/share/applications/shadow-client-appimage.desktop \
      --replace "Exec=AppRun --no-sandbox %U" "Exec=shadow %U"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Shadow PC client for video streaming (AppImage build)";
    homepage = "https://shadow.tech";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "shadow";
  };
}
