{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.icarusModManager;
  inherit (lib)
    getExe'
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  versionUnderscored = lib.replaceStrings [ "." ] [ "_" ] cfg.version;

  sourceUrl =
    if cfg.source != null then
      cfg.source
    else
      "https://github.com/Jimk72/Icarus_Software/raw/main/Icarus_Mod_Manager_${versionUnderscored}.zip";

  dataPackage = pkgs.stdenvNoCC.mkDerivation {
    pname = "icarus-mod-manager-data";
    inherit (cfg) version;

    src = pkgs.fetchzip {
      url = sourceUrl;
      stripRoot = false;
      inherit (cfg) hash;
    };

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/icarus-mod-manager"
      cp -R . "$out/share/icarus-mod-manager"
      runHook postInstall
    '';
  };

  iniSetScript = pkgs.writeText "icarus-mod-manager-ini-set.py" ''
    import sys
    from pathlib import Path

    path = Path(sys.argv[1])
    section = sys.argv[2]
    key = sys.argv[3]
    value = sys.argv[4]

    if path.exists():
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    else:
        lines = []

    section_header = f"[{section}]"
    section_start = None
    section_end = len(lines)

    for index, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if stripped.lower() == section_header.lower():
                section_start = index
                section_end = len(lines)
            elif section_start is not None:
                section_end = index
                break

    if section_start is None:
        if lines and lines[-1] != "":
            lines.append("")
        lines.extend([section_header, f"{key}={value}"])
    else:
        key_prefix = f"{key.lower()}="
        for index in range(section_start + 1, section_end):
            if lines[index].strip().lower().startswith(key_prefix):
                lines[index] = f"{key}={value}"
                break
        else:
            lines.insert(section_end, f"{key}={value}")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
  '';

  defaultDataDir =
    let
      xdgHome = config.xdg.dataHome or null;
    in
    if xdgHome != null then
      "${xdgHome}/icarus-mod-manager"
    else
      "${config.home.homeDirectory}/.local/share/icarus-mod-manager";

  wine = cfg.winePackage;
  wineBin = getExe' wine "wine";
  winebootBin = getExe' wine "wineboot";
  wineserverBin = getExe' wine "wineserver";
  winepathBin = getExe' wine "winepath";

  fontPackages = [
    pkgs.dejavu_fonts
    pkgs.liberation_ttf
  ];

  wineFontFiles = [
    "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf"
    "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans-Bold.ttf"
    "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf"
    "${pkgs.liberation_ttf}/share/fonts/truetype/LiberationMono-Bold.ttf"
    "${pkgs.liberation_ttf}/share/fonts/truetype/LiberationMono-Regular.ttf"
    "${pkgs.liberation_ttf}/share/fonts/truetype/LiberationSans-Bold.ttf"
    "${pkgs.liberation_ttf}/share/fonts/truetype/LiberationSans-Regular.ttf"
    "${pkgs.liberation_ttf}/share/fonts/truetype/LiberationSerif-Bold.ttf"
    "${pkgs.liberation_ttf}/share/fonts/truetype/LiberationSerif-Regular.ttf"
  ];

  launcher = pkgs.writeShellApplication {
    name = "icarus-mod-manager";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.python3
      pkgs.xrandr
      wine
    ];

    text = ''
      set -euo pipefail

      prefix="${cfg.winePrefix}"
      mutable_dir="${cfg.mutableDataDir}"
      app_dir="$mutable_dir"
      ini_file="$app_dir/IcarusModManager.ini"
      smoke_seconds="${toString cfg.smokeTestSeconds}"

      export WINEPREFIX="$prefix"
      export WINEDEBUG="''${WINEDEBUG:--all}"
      export WINEDLLOVERRIDES="winewayland.drv=d,''${WINEDLLOVERRIDES:-}"
      export WINEESYNC=1
      export WINEFSYNC=1
      export GDK_SCALE=1
      export GDK_DPI_SCALE=1
      export GTK_IM_MODULE=xim
      export QT_IM_MODULE=xim
      export XMODIFIERS='@im=none'

      mkdir -p "$mutable_dir" "$(dirname "$prefix")"

      if [ ! -e "$mutable_dir/IcarusModManager.exe" ]; then
        echo "Priming writable Icarus Mod Manager directory at $mutable_dir..."
        cp -R --no-preserve=mode,ownership "${dataPackage}/share/icarus-mod-manager/." "$mutable_dir/"
      fi

      set_ini_value() {
        python3 ${iniSetScript} "$1" "$2" "$3" "$4"
      }

      progress() {
        if [ "''${IMM_VERBOSE:-0}" = "1" ]; then
          echo "[icarus-mod-manager] $*" >&2
        fi
      }

      windows_path() {
        local converted
        converted="$(timeout 5s "${winepathBin}" -w "$1" 2>/dev/null || true)"
        if [ -n "$converted" ]; then
          printf '%s\n' "$converted"
        else
          python3 -c 'import sys; print("Z:" + sys.argv[1].replace("/", "\\"))' "$1"
        fi
      }

      install_fonts() {
        local fonts_dir="$prefix/drive_c/windows/Fonts"
        mkdir -p "$fonts_dir"

        for font_file in ${lib.escapeShellArgs wineFontFiles}; do
          if [ -f "$font_file" ]; then
            cp -n --no-preserve=mode,ownership "$font_file" "$fonts_dir/" 2>/dev/null || true
          fi
        done
      }

      configure_registry() {
        if [ -f "$prefix/.icarus-registry-configured" ]; then
          progress "Wine registry already configured"
          return
        fi

        wine_reg_add() {
          timeout 2s "${wineBin}" reg add "$@" >/dev/null 2>&1 || true
        }

        progress "configuring Wine registry"
        wine_reg_add 'HKCU\Software\Wine\Drivers' /v Graphics /t REG_SZ /d x11 /f
        wine_reg_add 'HKCU\Software\Wine\AppDefaults\IcarusModManager.exe\DllOverrides' /v winewayland.drv /t REG_SZ /d disabled /f

        for hive in \
          'HKCU\Software\Wine\Fonts\Replacements' \
          'HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
        do
          wine_reg_add "$hive" /v 'MS Sans Serif' /t REG_SZ /d 'Liberation Sans' /f
          wine_reg_add "$hive" /v 'MS Serif' /t REG_SZ /d 'Liberation Serif' /f
          wine_reg_add "$hive" /v System /t REG_SZ /d 'Liberation Sans' /f
          wine_reg_add "$hive" /v Fixedsys /t REG_SZ /d 'Liberation Mono' /f
          wine_reg_add "$hive" /v 'MS Shell Dlg' /t REG_SZ /d 'Liberation Sans' /f
          wine_reg_add "$hive" /v 'MS Shell Dlg 2' /t REG_SZ /d 'Liberation Sans' /f
          wine_reg_add "$hive" /v 'Segoe UI' /t REG_SZ /d 'Liberation Sans' /f
          wine_reg_add "$hive" /v Tahoma /t REG_SZ /d 'Liberation Sans' /f
        done

        wine_reg_add 'HKCU\Control Panel\Desktop' /v LogPixels /t REG_DWORD /d 96 /f
        wine_reg_add 'HKCU\Control Panel\Desktop' /v Win8DpiScaling /t REG_DWORD /d 0 /f
        touch "$prefix/.icarus-registry-configured"
      }

      configure_app_files() {
        if [ -f "$ini_file" ] && [ "''${IMM_WINE_KEEP_NEW_SKIN:-0}" != "1" ]; then
          local orig_skin_dir="$app_dir/Skins_Folder/Original Skin"
          if [ -d "$orig_skin_dir" ]; then
            set_ini_value "$ini_file" Folder Skin "$(windows_path "$orig_skin_dir")"
          fi

          local skin_ini="$orig_skin_dir/Skin.ini"
          if [ -f "$skin_ini" ]; then
            set_ini_value "$skin_ini" Colors FontColors "#FFB420"
            set_ini_value "$skin_ini" Colors UassetFontColors "#D3E5AE"
            set_ini_value "$skin_ini" Colors ButtonsFontColors "#D3E5AE"
            set_ini_value "$skin_ini" Colors ButtonsMouseOverFontColor "#000000"
            set_ini_value "$skin_ini" Colors ButtonsPressedFontColor "#D3E5AE"
          fi
        fi

        if [ -f "$ini_file" ] && [ "''${IMM_WINE_KEEP_4KUI:-0}" != "1" ]; then
          set_ini_value "$ini_file" Settings 4KUI false
        fi
      }

      ensure_prefix_ready() {
        if [ -f "$prefix/.icarus-prefix-ready" ]; then
          progress "Wine prefix already initialized"
          return
        fi

        progress "running wineboot"
        timeout 45s "${winebootBin}" -u >/dev/null 2>&1 || true
        progress "waiting for wineserver"
        timeout 60s "${wineserverBin}" -w >/dev/null 2>&1 || true
        progress "installing fonts"
        install_fonts
        configure_registry

        local appdata
        progress "checking AppData"
        appdata="$(timeout 30s "${wineBin}" cmd.exe /c echo '%AppData%' 2>/dev/null | tr -d '\r' | tail -n 1 || true)"
        if [ -z "$appdata" ] || [ "$appdata" = "%AppData%" ]; then
          echo "Warning: Wine did not return %AppData%; continuing because Icarus Mod Manager does not need dotnet/winetricks." >&2
        fi
        if [ -e "$prefix/drive_c/windows/system32/kernel32.dll" ]; then
          touch "$prefix/.icarus-prefix-ready"
        else
          echo "Warning: Wine prefix does not contain kernel32.dll yet; next launch will re-run wineboot." >&2
        fi
      }

      run_smoke_test() {
        local log rc
        log="$(mktemp)"
        set +e
        timeout "$smoke_seconds" "${wineBin}" "$app_dir/IcarusModManager.exe" >"$log" 2>&1
        rc=$?
        timeout 5s "${wineserverBin}" -k >/dev/null 2>&1 || true
        set -e

        if grep -E 'unimplemented function|SystemFunction036|WINEARCH is set|returned empty string' "$log" >&2; then
          echo "Icarus Mod Manager smoke test failed; Wine reported a known broken runtime path." >&2
          echo "Log: $log" >&2
          return 1
        fi

        if [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]; then
          echo "Icarus Mod Manager smoke test passed."
          rm -f "$log"
          return 0
        fi

        echo "Icarus Mod Manager smoke test failed with exit code $rc." >&2
        echo "Log: $log" >&2
        cat "$log" >&2 || true
        return "$rc"
      }

      ensure_prefix_ready
      progress "configuring app files"
      configure_app_files

      case "''${1:-}" in
        --self-test)
          test -f "$app_dir/IcarusModManager.exe"
          echo "Icarus Mod Manager prefix and app files are ready."
          ;;
        --smoke-test)
          run_smoke_test
          ;;
        *)
          cd "$app_dir"
          exec "${wineBin}" "$app_dir/IcarusModManager.exe" "$@"
          ;;
      esac
    '';
  };
in
{
  options.programs.icarusModManager = {
    enable = mkEnableOption "Icarus Mod Manager Wine launcher";

    version = mkOption {
      type = types.str;
      default = "2.4.0";
      description = "Upstream release version to download.";
    };

    source = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Override URL to the standalone zip release.";
    };

    hash = mkOption {
      type = types.str;
      default = "sha256-z4Ns76YtaWgCzUtvddOu7dWJdpCxTpywVoAxLDAynck=";
      description = "Hash of the downloaded archive in SRI format.";
    };

    winePackage = mkOption {
      type = types.package;
      default = pkgs.wineWow64Packages.full;
      defaultText = "pkgs.wineWow64Packages.full";
      description = "Wine package used to run Icarus Mod Manager.";
    };

    winePrefix = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.local/share/wineprefixes/icarus-mod-manager";
      description = "Wine prefix used for Icarus Mod Manager.";
    };

    mutableDataDir = mkOption {
      type = types.str;
      default = defaultDataDir;
      description = "Writable directory where the manager files are copied and launched.";
    };

    smokeTestSeconds = mkOption {
      type = types.ints.positive;
      default = 20;
      description = "Seconds to let the GUI run during `icarus-mod-manager --smoke-test`.";
    };

    autoInstallDotnet80 = mkOption {
      type = types.bool;
      default = false;
      description = "Deprecated no-op. Icarus Mod Manager is a native Win32 executable and does not need dotnetdesktop8.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      launcher
      dataPackage
    ]
    ++ fontPackages;

    xdg.desktopEntries."icarus-mod-manager" = {
      name = "Icarus Mod Manager";
      comment = "Run Icarus Mod Manager via Wine";
      exec = "icarus-mod-manager";
      categories = [
        "Game"
        "Utility"
      ];
      terminal = false;
    };
  };
}
