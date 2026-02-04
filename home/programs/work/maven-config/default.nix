{
  config,
  pkgs,
  lib,
  ...
}:

let
  cfg = config.programs."maven-config";
  jdk = pkgs.temurin-bin-17;
  jdkHome = "${jdk}"; # <-- use the JDK root, not lib/openjdk
in
{
  options.programs."maven-config" = {
    enable = lib.mkEnableOption "Maven/JDK tooling";
  };

  config = lib.mkMerge [
    {
      programs."maven-config".enable = lib.mkDefault true;
    }
    (lib.mkIf cfg.enable {
      home.packages = [
        # Wrap Maven to enforce correct JAVA_HOME
        (pkgs.writeShellScriptBin "mvn" ''
          export JAVA_HOME="${jdkHome}"
          export PATH="${jdkHome}/bin:$PATH"
          exec "${pkgs.maven}/bin/mvn" "$@"
        '')
        jdk
      ];

      home.sessionVariables = {
        JAVA_HOME = jdkHome;
      };
    })
  ];
}
