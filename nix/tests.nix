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
          ${pkgs.wineWow64Packages.full}/bin/wineserver -k >/dev/null 2>&1 || true
          sleep 1
          ${pkgs.procps}/bin/pkill -u "$(id -u)" -f 'IcarusModManager\.exe|explorer\.exe|wine|wineboot|services\.exe|rpcss\.exe|winedevice\.exe|wineserver' >/dev/null 2>&1 || true
          kill "$xvfb_pid" >/dev/null 2>&1 || true
        }
        trap cleanup EXIT

        sleep 1
        export DISPLAY="$display"
        "$@"
      '';

      icarusUpdateDatabaseTest = pkgs.writeShellScriptBin "imm-update-database-test" ''
        set -euo pipefail

        icarus-mod-manager >/tmp/imm-update-db.log 2>&1 &
        app_pid="$!"

        cleanup() {
          status="$?"
          if [ "$status" -ne 0 ]; then
            echo "imm-update-database-test failed with status $status" >&2
            echo "--- windows before ---" >&2
            cat /tmp/imm-window-names >&2 || true
            echo "--- windows after ---" >&2
            cat /tmp/imm-window-name-after >&2 || true
            echo "--- processes ---" >&2
            ps -ef | grep -E 'Icarus|wine|wineserver|explorer' >&2 || true
            echo "--- app log ---" >&2
            cat /tmp/imm-update-db.log >&2 || true
          fi
          kill "$app_pid" >/dev/null 2>&1 || true
          exit "$status"
        }
        trap cleanup EXIT

        i=0
        while [ "$i" -lt 60 ]; do
          ${pkgs.xdotool}/bin/xdotool search --name '.*' 2>/dev/null | while read -r window_id; do
            ${pkgs.xdotool}/bin/xdotool getwindowname "$window_id" 2>/dev/null || true
          done >/tmp/imm-window-names
          if ${pkgs.xdotool}/bin/xdotool search --name 'Icarus|Mod Downloads' >/tmp/imm-window-id 2>/dev/null; then
            break
          fi
          i=$((i + 1))
          sleep 1
        done

        if [ ! -s /tmp/imm-window-id ]; then
          cat /tmp/imm-window-names >&2 || true
          cat /tmp/imm-update-db.log >&2 || true
          exit 1
        fi
        window_id="$(head -n 1 /tmp/imm-window-id)"
        ${pkgs.xdotool}/bin/xdotool windowactivate "$window_id" || true
        ${pkgs.xdotool}/bin/xdotool mousemove --window "$window_id" 62 50 click 1
        sleep 20
        if ! ${pkgs.xdotool}/bin/xdotool getwindowname "$window_id" >/tmp/imm-window-name-after 2>/dev/null; then
          cat /tmp/imm-update-db.log >&2 || true
          exit 1
        fi
        if ps -p "$app_pid" -o stat= | grep -q R; then
          echo "Icarus Mod Manager stayed CPU-runnable after Update Database click." >&2
          cat /tmp/imm-window-names >&2 || true
          cat /tmp/imm-window-name-after >&2 || true
          cat /tmp/imm-update-db.log >&2 || true
          exit 1
        fi
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
                icarusContentDir = "/home/icarus/Icarus/Icarus/Content";
                mutableDataDir = "/home/icarus/.local/share/icarus-mod-manager-test";
                winePrefix = "/home/icarus/.local/share/wineprefixes/icarus-mod-manager-test";
                smokeTestSeconds = 15;
              };
            };

            environment.systemPackages = [
              icarusUpdateDatabaseTest
              icarusVmRunner
              pkgs.procps
              pkgs.xdotool
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
          machine.succeed("su - icarus -c 'mkdir -p /home/icarus/Icarus/Icarus/Content/Data /home/icarus/Icarus/Icarus/Content/Paks/mods && touch /home/icarus/Icarus/Icarus/Content/Data/data.pak'")
          machine.succeed("su - icarus -c 'IMM_VERBOSE=1 run-imm-xvfb timeout 240s icarus-mod-manager --self-test'")
          machine.succeed("su - icarus -c 'printf %s trailing-bytes > /home/icarus/.local/share/icarus-mod-manager-test/repos.json'")
          machine.succeed("su - icarus -c 'IMM_VERBOSE=1 run-imm-xvfb timeout 120s imm-update-database-test'")
          machine.succeed("su - icarus -c 'IMM_VERBOSE=1 run-imm-xvfb timeout 180s icarus-mod-manager --smoke-test'")
          machine.succeed("su - icarus -c 'test ! -e /home/icarus/.local/share/icarus-mod-manager-test/repos.json || ${pkgs.python3}/bin/python3 -m json.tool /home/icarus/.local/share/icarus-mod-manager-test/repos.json >/dev/null'")
          machine.succeed("su - icarus -c 'find /home/icarus/.local/share/icarus-mod-manager-test -maxdepth 1 -name repos.json.corrupt.\\* -print -quit | grep -q .'")
          machine.succeed("su - icarus -c 'test -f /home/icarus/.local/share/icarus-mod-manager-test/UnrealPak/Engine/Binaries/Win64/UnrealPak.exe'")
          machine.succeed("su - icarus -c 'test -f /home/icarus/.local/share/icarus-mod-manager-test/data/Items/D_ItemsStatic.json'")
          machine.succeed("su - icarus -c 'grep -F \"IcarusContent=Z:\\\\home\\\\icarus\\\\Icarus\\\\Icarus\\\\Content\" /home/icarus/.local/share/icarus-mod-manager-test/IcarusModManager.ini'")
          machine.succeed("su - icarus -c 'grep -F \"UE4PakEXE=Z:\\\\home\\\\icarus\\\\.local\\\\share\\\\icarus-mod-manager-test\\\\UnrealPak\\\\Engine\\\\Binaries\\\\Win64\\\\UnrealPak.exe\" /home/icarus/.local/share/icarus-mod-manager-test/IcarusModManager.ini'")
          machine.succeed("su - icarus -c '${pkgs.python3}/bin/python3 - <<\"PY\"\nimport json\nimport zipfile\nfrom pathlib import Path\n\napp = Path(\"/home/icarus/.local/share/icarus-mod-manager-test\")\narchive = Path(\"/tmp/Test_Mod.EXMODZ\")\nwith zipfile.ZipFile(archive, \"w\") as handle:\n    handle.writestr(\"Extracted Mods/Test_Mod.EXMOD\", \"test exmod\")\n    handle.writestr(\"Test_Mod/readme.txt\", \"test readme\")\n(app / \"repos.json\").write_text(\"{}\\n\", encoding=\"utf-8\")\n(app / \"mods.json\").write_text(json.dumps({\"documents\": [{\"fields\": {\"name\": {\"stringValue\": \"Test Mod\"}, \"author\": {\"stringValue\": \"Nix\"}, \"version\": {\"stringValue\": \"1.0\"}, \"compatibility\": {\"stringValue\": \"All\"}, \"files\": {\"mapValue\": {\"fields\": {\"exmodz\": {\"stringValue\": archive.as_uri()}}}}}}]}) + \"\\n\", encoding=\"utf-8\")\nPY'")
          machine.succeed("su - icarus -c 'IMM_VERBOSE=1 run-imm-xvfb timeout 120s icarus-mod-manager --download-mod \"Test Mod\"'")
          machine.succeed("su - icarus -c 'grep -F \"test exmod\" /home/icarus/.local/share/icarus-mod-manager-test/Extracted_Mods/Test_Mod.EXMOD'")
          machine.succeed("su - icarus -c 'grep -F \"test readme\" /home/icarus/.local/share/icarus-mod-manager-test/Test_Mod/readme.txt'")
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
