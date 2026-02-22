{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  perSystem =
    { config, ... }:
    {
      treefmt = {
        flakeCheck = false;
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.statix.enable = true;
        programs.deadnix.enable = true;
        settings.global.excludes = [
          "result/**"
          "examples/**"
          ".git/**"
        ];
      };

      formatter = config.treefmt.build.wrapper;
    };
}
