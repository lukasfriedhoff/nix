{ self, ... }:
{
  perSystem =
    { lib, ... }:
    let
      withIntegrationTests = lib.filterAttrs (
        _: configuration: builtins.hasAttr "integrationTests" configuration.options
      ) self.nixosConfigurations;

      extractIntegrationTests = lib.mapAttrsToList (
        _: config: lib.attrsToList config.config.integrationTests
      ) withIntegrationTests;

      collectAndMerge = list: builtins.listToAttrs (builtins.concatLists list);
    in
    {
      checks = collectAndMerge extractIntegrationTests;
    };

  flake.nixosModules.integrationTests =
    { lib, ... }:
    {
      options.integrationTests = lib.mkOption {
        type = lib.types.attrsOf lib.types.package;
        default = { };
        description = "pkgs.nixosTest derivations to include in nix flake check.";
      };
    };
}
