{
  lib,
  fetchPypi,
  python3Packages,
}:

python3Packages.buildPythonApplication (finalAttrs: {
  pname = "bpytop";
  version = "1.0.68";

  format = "setuptools";
  doCheck = false;

  src = fetchPypi {
    inherit (finalAttrs) pname version;
    sha256 = "53b66788e8d7c7abbab43c6275fa1c3b2316e56e46f7a093f2f4dfb397549bb2";
  };

  nativeBuildInputs = [
    python3Packages.setuptools
    python3Packages.wheel
  ];

  dependencies = [ python3Packages.psutil ];

  postInstall = ''
    install -d $out/share/bpytop/themes
    install -m 0644 themes/*.theme $out/share/bpytop/themes/
  '';

  meta = with lib; {
    description = "Python reimplementation of btop";
    homepage = "https://github.com/vladkens/bpytop";
    license = licenses.asl20;
    mainProgram = "bpytop";
    platforms = platforms.linux ++ platforms.darwin;
  };
})
