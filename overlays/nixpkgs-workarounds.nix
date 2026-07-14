_final: prev:

let
  fixedI686WaylandPkgConfig = ''
        fixedWaylandPcDir="$NIX_BUILD_TOP/fixed-wayland-pkgconfig"
        mkdir -p "$fixedWaylandPcDir"

        cat > "$fixedWaylandPcDir/wayland-client.pc" <<EOFPC
    Name: Wayland Client
    Description: Wayland client side library
    Version: ${prev.pkgsi686Linux.wayland.version}
    Libs: -L${prev.pkgsi686Linux.wayland.out}/lib -lwayland-client -lm
    Libs.private: -pthread -lrt
    Cflags: -I${prev.wayland.dev}/include
    EOFPC

        cat > "$fixedWaylandPcDir/wayland-server.pc" <<EOFPC
    Name: Wayland Server
    Description: Server side implementation of the Wayland protocol
    Version: ${prev.pkgsi686Linux.wayland.version}
    Requires.private: libffi
    Libs: -L${prev.pkgsi686Linux.wayland.out}/lib -lwayland-server -lm
    Libs.private: -pthread -lrt
    Cflags: -I${prev.wayland.dev}/include
    EOFPC

        cat > "$fixedWaylandPcDir/wayland-egl-backend.pc" <<EOFPC
    Name: wayland-egl-backend
    Description: Backend wayland-egl interface
    Version: 3
    Cflags: -I${prev.wayland.dev}/include
    EOFPC

        cat > "$fixedWaylandPcDir/wayland-egl.pc" <<EOFPC
    Name: wayland-egl
    Description: Frontend wayland-egl library
    Version: 18.1.0
    Requires: wayland-client
    Libs: -L${prev.pkgsi686Linux.wayland.out}/lib -lwayland-egl
    Cflags: -I${prev.wayland.dev}/include
    EOFPC

        cat > "$fixedWaylandPcDir/wayland-cursor.pc" <<EOFPC
    Name: Wayland Cursor
    Description: Wayland cursor helper library
    Version: ${prev.pkgsi686Linux.wayland.version}
    Requires.private: wayland-client
    Libs: -L${prev.pkgsi686Linux.wayland.out}/lib -lwayland-cursor
    Cflags: -I${prev.wayland.dev}/include
    EOFPC

        cat > "$fixedWaylandPcDir/wayland-protocols.pc" <<EOFPC
    Name: Wayland Protocols
    Description: Wayland protocol files
    Version: ${prev.wayland-protocols.version}
    pkgdatadir=${prev.wayland-protocols}/share/wayland-protocols
    EOFPC

        cat > "$fixedWaylandPcDir/wayland-scanner.pc" <<EOFPC
    Name: Wayland Scanner
    Description: Wayland scanner
    Version: ${prev.wayland-scanner.version}
    Cflags: -I${prev.wayland-scanner.dev}/include
    wayland_scanner=${prev.wayland-scanner.bin}/bin/wayland-scanner
    EOFPC

        export PKG_CONFIG_PATH="$fixedWaylandPcDir:$PKG_CONFIG_PATH"
        export PKG_CONFIG_PATH_FOR_BUILD="$fixedWaylandPcDir:''${PKG_CONFIG_PATH_FOR_BUILD:-}"
  '';
in
{
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (_python-final: python-prev: {
      python-gnupg = python-prev.python-gnupg.overridePythonAttrs (_old: {
        doCheck = false;
      });
    })
  ];

  pkgsi686Linux = prev.pkgsi686Linux // {
    egl-wayland = prev.pkgsi686Linux.egl-wayland.overrideAttrs (old: {
      preConfigure = (old.preConfigure or "") + fixedI686WaylandPkgConfig;
    });

    egl-wayland2 = prev.pkgsi686Linux.egl-wayland2.overrideAttrs (old: {
      preConfigure = (old.preConfigure or "") + fixedI686WaylandPkgConfig;
    });
  };
}
