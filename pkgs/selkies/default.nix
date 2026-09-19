{
  lib,
  fetchFromGitHub,
  callPackage,
  python3Packages,
}:

# Selkies: browser-based (WebSocket/WebRTC) remote desktop streaming server.
# Upstream has no usable release artifacts for 2.x (PyPI still carries 1.6),
# so the server, its two Rust engines and the web client are all pinned to
# coherent main-branch commits (upstream CI tests these three together).
let
  version = "2.1.0-unstable-2026-09-17";

  selkiesSrc = fetchFromGitHub {
    owner = "selkies-project";
    repo = "selkies";
    rev = "15e3eff9aaf65a3186b0d179f2d3bd2d623806da";
    hash = "sha256-4H0GSGgpRQNGq30Urita2n9hXWE1MldVU6vqT+W/G04=";
  };

  pixelflux = callPackage ./pixelflux.nix { inherit python3Packages; };
  pcmflux = callPackage ./pcmflux.nix { inherit python3Packages; };
  web = callPackage ./web.nix {
    inherit selkiesSrc;
    selkiesVersion = version;
  };
in
python3Packages.buildPythonApplication {
  pname = "selkies";
  inherit version;
  pyproject = true;

  src = selkiesSrc;

  postPatch = ''
    # Stamp a PEP 440 version the way the Dockerfile/CI wheel build does.
    substituteInPlace pyproject.toml \
      --replace-fail 'version = "0.0.0.dev0"' 'version = "2.1.0"'

    # Bundle the built web client where the wheel expects its package data.
    rm -rf src/selkies/selkies_web
    cp -r ${web} src/selkies/selkies_web
    chmod -R u+w src/selkies/selkies_web
  '';

  build-system = with python3Packages; [ setuptools ];

  # Upstream floors chase the newest releases; nixpkgs is the compatibility
  # authority here.
  pythonRelaxDeps = true;

  dependencies =
    (with python3Packages; [
      prometheus-client
      msgpack
      psutil
      watchdog
      pillow
      pulsectl-asyncio
      dnspython
      cffi
      cryptography
      google-crc32c
      pyee
      pylibsrtp
      pyopenssl
      aiohttp
      aiofiles
      uvloop
      nvidia-ml-py
    ])
    ++ [
      pixelflux
      pcmflux
    ];

  pythonImportsCheck = [ "selkies" ];

  passthru = {
    inherit pixelflux pcmflux web;
  };

  meta = {
    description = "Low-latency HTML5 remote desktop / game streaming platform";
    homepage = "https://github.com/selkies-project/selkies";
    license = lib.licenses.mpl20;
    platforms = lib.platforms.linux;
    mainProgram = "selkies";
  };
}
