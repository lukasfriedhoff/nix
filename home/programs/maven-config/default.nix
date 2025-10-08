{ pkgs, ... }:

{
  # Install Maven bound to Temurin 17
  home.packages = [
    (pkgs.maven.override { jdk_headless = pkgs.temurin-bin-17; })
    pkgs.temurin-bin-17
  ];

  # Make Temurin 17 the default JDK on your shell sessions
  home.sessionVariables = {
    JAVA_HOME = "${pkgs.temurin-bin-17}/lib/openjdk";
  };
  home.sessionPath = [ "${pkgs.temurin-bin-17}/bin" ];
}