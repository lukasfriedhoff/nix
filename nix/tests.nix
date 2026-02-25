{ self, inputs, ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      ...
    }:
    let
      withIntegrationTests = lib.filterAttrs (
        _: configuration: builtins.hasAttr "integrationTests" configuration.options
      ) self.nixosConfigurations;

      extractIntegrationTests = lib.mapAttrsToList (
        _: config: lib.attrsToList config.config.integrationTests
      ) withIntegrationTests;

      collectAndMerge = list: builtins.listToAttrs (builtins.concatLists list);

      pipewireTest = pkgs.testers.nixosTest {
        name = "pipewire-stack";
        nodes.machine =
          { ... }:
          {
            imports = [
              ../modules/features/audio/pipewire/nixos.nix
            ];
            lukasf.pipewire.enable = true;
            system.stateVersion = "25.05";
          };
        testScript = ''
          machine.succeed("test -e /etc/systemd/user/pipewire.service")
          machine.succeed("test -e /etc/systemd/user/pipewire-pulse.service")
        '';
      };

      gcRootsCleanerTest = pkgs.testers.nixosTest {
        name = "nix-gc-roots-cleaner";
        nodes.machine =
          { ... }:
          {
            imports = [
              ../modules/features/nix/gc-roots-cleaner/nixos.nix
            ];
            nix.gc = {
              automatic = true;
              dates = "hourly";
            };
            system.stateVersion = "25.05";
          };
        testScript = ''
          machine.wait_for_unit("nix-gc-roots-cleaner.timer")
          machine.succeed("test -e /etc/systemd/system/nix-gc-roots-cleaner.service")
        '';
      };

      nixRegistryTest = pkgs.testers.nixosTest {
        name = "nix-registry";
        nodes.machine =
          { ... }:
          {
            imports = [
              ../modules/features/nix/registry/nixos.nix
            ];
            _module.args.inputs = inputs;
            lukasf.nixRegistry.enable = true;
            system.stateVersion = "25.05";
          };
        testScript = ''
          machine.succeed("test -s /etc/nix/registry.json")
        '';
      };

      shadowClientTest = pkgs.testers.nixosTest {
        name = "shadow-client-appimage";
        nodes.machine =
          { ... }:
          {
            imports = [
              ../modules/features/shadow-tech/nixos.nix
            ];
            lukasf.shadowTech.enable = true;
            system.stateVersion = "25.05";
          };
        testScript = ''
          machine.wait_for_unit("multi-user.target")
          machine.succeed("test -x /run/current-system/sw/bin/shadow")
          machine.succeed("test -f /run/current-system/sw/share/applications/shadow-client-appimage.desktop")
          machine.succeed("test -u /run/wrappers/bin/chrome-sandbox || test -u /run/wrappers/bin/shadow-chrome-sandbox")
        '';
      };
    in
    {
      checks = {
        pipewire-stack = pipewireTest;
        nix-gc-roots-cleaner = gcRootsCleanerTest;
        nix-registry = nixRegistryTest;
        shadow-client-appimage = shadowClientTest;
      }
      // collectAndMerge extractIntegrationTests;
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
