{ pkgs, lib, ... }:

let
  version = "1.10.0";
  pname = "dsbulk";
in
pkgs.stdenv.mkDerivation {
  inherit pname version;

  src = pkgs.fetchzip {
    url = "https://downloads.datastax.com/dsbulk/${pname}-${version}.tar.gz";
    sha256 = "sha256-yp1FH7fLuUQlnDt49NrUCkqUan7VsmPZlqas5HfAVoI=";
  };

  buildInputs = [ pkgs.makeWrapper pkgs.temurin-bin-17 ];

  dontBuild = true;

  installPhase = ''
    mkdir -p $out/bin $out/share/${pname}
    cp -r * $out/share/${pname}

    wrapProgram $out/share/${pname}/bin/dsbulk \
      --prefix PATH : ${pkgs.temurin-bin-17}/bin \
      --set JAVA_HOME ${pkgs.temurin-bin-17} \
      --set DSBULK_JAVA_OPTS "${lib.optionalString (lib.versionAtLeast version "1.10.0") "-Dfile.encoding=UTF-8"}"

    ln -s $out/share/${pname}/bin/dsbulk $out/bin/dsbulk
  '';

  meta = with lib; {
    description = "DataStax Bulk Loader CLI (dsbulk)";
    homepage = "https://docs.datastax.com/en/dsbulk/installing/install.html";
    license = licenses.asl20;
    platforms = platforms.unix;
  };
}