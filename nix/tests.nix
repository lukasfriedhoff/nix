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

      icarusVmRunner = pkgs.writeShellScriptBin "run-imm-xvfb" ''
        set -euo pipefail

        display="''${IMM_XVFB_DISPLAY:-:99}"
        ${pkgs.xvfb}/bin/Xvfb "$display" -screen 0 1280x720x24 -nolisten tcp >/tmp/imm-xvfb.log 2>&1 &
        xvfb_pid="$!"

        cleanup() {
          ${pkgs.procps}/bin/pkill -u "$(id -u)" -f 'wineserver|wine|wineboot|explorer\.exe|services\.exe|rpcss\.exe|winedevice\.exe|IcarusModManager\.exe' >/dev/null 2>&1 || true
          kill "$xvfb_pid" >/dev/null 2>&1 || true
        }
        trap cleanup EXIT

        sleep 1
        export DISPLAY="$display"
        "$@"
      '';

      icarusModManagerTest = pkgs.testers.nixosTest {
        name = "icarus-mod-manager";
        nodes.machine =
          { ... }:
          {
            imports = [
              inputs.home-manager.nixosModules.home-manager
            ];

            users.users.icarus = {
              isNormalUser = true;
              password = "icarus-test";
            };

            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.icarus = {
              imports = [
                ../modules/features/gaming/icarus-mod-manager/home.nix
              ];

              home.stateVersion = "26.05";
              programs.icarusModManager = {
                enable = true;
                mutableDataDir = "/home/icarus/.local/share/icarus-mod-manager-test";
                winePrefix = "/home/icarus/.local/share/wineprefixes/icarus-mod-manager-test";
                smokeTestSeconds = 15;
              };
            };

            environment.systemPackages = [
              icarusVmRunner
              pkgs.procps
              pkgs.xvfb
            ];

            virtualisation = {
              cores = 2;
              memorySize = 4096;
            };

            system.stateVersion = "26.05";
          };
        testScript = ''
          machine.wait_for_unit("multi-user.target")
          machine.wait_for_unit("home-manager-icarus.service")
          machine.succeed("su - icarus -c 'IMM_VERBOSE=1 run-imm-xvfb sh -c \"timeout 240s icarus-mod-manager --self-test && timeout 180s icarus-mod-manager --smoke-test\"'")
        '';
      };
    in
    {
      checks = {
        pipewire-stack = pipewireTest;
        nix-gc-roots-cleaner = gcRootsCleanerTest;
        nix-registry = nixRegistryTest;
        shadow-client-appimage = shadowClientTest;
        icarus-mod-manager = icarusModManagerTest;
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
