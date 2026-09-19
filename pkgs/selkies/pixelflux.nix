{
  lib,
  fetchFromGitHub,
  rustPlatform,
  cargo,
  rustc,
  python3Packages,
  pkg-config,
  cmake,
  nasm,
  x264,
  libjpeg_turbo,
  ffmpeg,
  libxcb,
  mesa,
  libgbm,
  libglvnd,
  libdrm,
  libinput,
  libxkbcommon,
  pixman,
  udev,
  wayland,
}:

# Video capture + encode engine of Selkies: a single Rust PyO3 extension doing
# XShm/DRI3 (and Wayland) capture with striped CPU encoding and full-frame
# VA-API/NVENC. Not on PyPI as an sdist (wheels only), so built from source.
python3Packages.buildPythonPackage rec {
  pname = "pixelflux";
  version = "2.1.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "selkies-project";
    repo = "pixelflux";
    rev = "1b9b0c7b0b71a352ae11d762488ab2982f52ba6c";
    hash = "sha256-B90G3xBCh0eG87hR3OdizpamjjjisMkvLvApBOXKz0A=";
  };

  # The Rust crate lives one level below the Python project root.
  cargoRoot = "pixelflux";
  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit src;
    name = "${pname}-${version}-cargo-deps";
    sourceRoot = "${src.name}/pixelflux";
    hash = "sha256-2dgcHix4jOf9p6Maz2tl1BxoNFbmhAsT2DIVU+xbK/E=";
  };

  build-system = with python3Packages; [
    setuptools
    setuptools-rust
  ];

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    rustPlatform.bindgenHook
    cargo
    rustc
    pkg-config
    # turbojpeg-sys builds its vendored libjpeg-turbo with cmake + nasm.
    cmake
    nasm
  ];
  # cmake here belongs to a -sys crate's vendored build, not the derivation.
  dontUseCmakeConfigure = true;

  buildInputs = [
    # GPL build (upstream default): libx264 carries software H.264.
    x264
    libjpeg_turbo
    # avcodec/avfilter for the VA-API encode path.
    ffmpeg
    libxcb
    mesa
    libgbm
    libdrm
    libinput
    libxkbcommon
    pixman
    udev
    wayland
  ];

  # Two libraries are opened with dlopen rather than linked — the
  # wayland-server crate is built with its `dlopen` feature, and smithay's
  # EGL backend loads libEGL.so.1 by name — so nix records no RUNPATH entry
  # for either. The import check still passes; what fails is the Wayland
  # capture thread, at runtime, with a panic inside a worker thread:
  #   Failed to load LibEGL: DlOpen { desc: "libEGL.so.1: cannot open ..." }
  # after which the compositor channel closes and every list_outputs call
  # fails. Put both on the extension's RUNPATH so dlopen resolves them.
  postFixup = ''
    patchelf --add-rpath "${
      lib.makeLibraryPath [
        wayland
        libglvnd
      ]
    }" \
      "$out/${python3Packages.python.sitePackages}/pixelflux.cpython-"*.so
  '';

  pythonImportsCheck = [ "pixelflux" ];

  meta = {
    description = "Web-native pixel delivery pipeline (Selkies capture/encode engine)";
    homepage = "https://github.com/selkies-project/pixelflux";
    license = lib.licenses.mpl20; # GPL overall when built with libx264
    platforms = lib.platforms.linux;
  };
}
