{
  lib,
  fetchFromGitHub,
  rustPlatform,
  cargo,
  rustc,
  python3Packages,
  pkg-config,
  cmake,
  libpulseaudio,
}:

# Audio counterpart of pixelflux: captures PCM from PulseAudio and encodes
# Opus (opusic-sys builds its vendored libopus via cmake).
python3Packages.buildPythonPackage rec {
  pname = "pcmflux";
  version = "2.1.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "selkies-project";
    repo = "pcmflux";
    rev = "f2edf0f7fa92dbd6d3e1faf5fa60001fae2ab4b5";
    hash = "sha256-EA0oRbeGoGUGA7QzqNY9pHjVDBWZ4Pol2zsm3nlDsT8=";
  };

  cargoRoot = "pcmflux";
  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit src;
    name = "${pname}-${version}-cargo-deps";
    sourceRoot = "${src.name}/pcmflux";
    hash = "sha256-242eUqJhM/qBPNa7ml7UjM4HsqRTb8lZGxplx2i4UA0=";
  };

  build-system = with python3Packages; [
    setuptools
    setuptools-rust
  ];

  nativeBuildInputs = [
    rustPlatform.cargoSetupHook
    cargo
    rustc
    pkg-config
    cmake
  ];
  dontUseCmakeConfigure = true;

  buildInputs = [ libpulseaudio ];

  pythonImportsCheck = [ "pcmflux" ];

  meta = {
    description = "PulseAudio PCM to Opus capture pipeline (Selkies audio engine)";
    homepage = "https://github.com/selkies-project/pcmflux";
    license = lib.licenses.mpl20;
    platforms = lib.platforms.linux;
  };
}
