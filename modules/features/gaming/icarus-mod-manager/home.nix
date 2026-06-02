{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.icarusModManager;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    optionalString
    ;

  versionUnderscored = lib.replaceStrings [ "." ] [ "_" ] cfg.version;

  sourceUrl =
    if cfg.source != null then
      cfg.source
    else
      "https://github.com/Jimk72/Icarus_Software/raw/main/Icarus_Mod_Manager_${versionUnderscored}.zip";

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
      mkdir -p $out/share/icarus-mod-manager
      cp -R . $out/share/icarus-mod-manager
      runHook postInstall
    '';
  };

  defaultDataDir =
    let
      xdgHome = config.xdg.dataHome or null;
    in
    if xdgHome != null then
      "${xdgHome}/icarus-mod-manager"
    else
      "${config.home.homeDirectory}/.local/share/icarus-mod-manager";

  launcher = pkgs.writeShellApplication {
    name = "icarus-mod-manager";
    runtimeInputs = [
      pkgs.wineWow64Packages.full
      pkgs.coreutils
      pkgs.python3
    ]
    ++ (if cfg.autoInstallDotnet80 then [ pkgs.winetricks ] else [ ]);
    text = ''
      set -euo pipefail
      prefix="${cfg.winePrefix}"
      mutable_dir="${cfg.mutableDataDir}"
      wine_bin="${pkgs.wineWow64Packages.full}/bin/wine"
      wineboot_bin="${pkgs.wineWow64Packages.full}/bin/wineboot"
      wineserver_bin="${pkgs.wineWow64Packages.full}/bin/wineserver"

      mkdir -p "$mutable_dir"
      if [ ! -e "$mutable_dir/IcarusModManager.exe" ]; then
        echo "Priming writable directory at $mutable_dir..."
        cp -R --no-preserve=mode,ownership "${dataPackage}/share/icarus-mod-manager/." "$mutable_dir/"
      fi

      app_dir="$mutable_dir"
      ini_file="$app_dir/IcarusModManager.ini"

      mkdir -p "$prefix"
      export WINEPREFIX="$prefix"
      export WINEDEBUG=-all
      export WINEDLLOVERRIDES="winewayland.drv=d,''${WINEDLLOVERRIDES:-}"
      export GDK_SCALE=1
      export GDK_DPI_SCALE=1
      # WinForms input on Wine can break when desktop IME integration is active.
      # Force a plain XIM path for this app.
      export GTK_IM_MODULE=xim
      export QT_IM_MODULE=xim
      export XMODIFIERS='@im=none'
      export WINE="$wine_bin"
      export WINEBOOT="$wineboot_bin"
      export WINESERVER="$wineserver_bin"

      ensure_wine_prefix_ready() {
        "$wineboot_bin" -u >/dev/null 2>&1 || true
        "$wineserver_bin" -w

        appdata="$("$wine_bin" cmd.exe /c echo '%AppData%' 2>/dev/null | tr -d '\r' | tail -n 1 || true)"
        if [ -z "$appdata" ] || [ "$appdata" = "%AppData%" ]; then
          echo "Icarus Mod Manager Wine prefix is not initialized correctly: %AppData% is empty." >&2
          echo "Move $prefix aside and rerun icarus-mod-manager to recreate the prefix." >&2
          exit 1
        fi
      }

      ensure_wine_prefix_ready

      # Prefer Wine's X11 path for IMM; Wayland driver can cause broken input/widgets.
      "$wine_bin" reg add \
        'HKCU\Software\Wine\Drivers' \
        /v 'Graphics' /t REG_SZ /d 'x11' /f >/dev/null 2>&1 || true
      "$wine_bin" reg add \
        'HKCU\Software\Wine\AppDefaults\IcarusModManager.exe\DllOverrides' \
        /v 'winewayland.drv' /t REG_SZ /d 'disabled' /f >/dev/null 2>&1 || true

      set_ini_value() {
        local file="$1"
        local section="$2"
        local key="$3"
        local value="$4"

        python3 ${iniSetScript} "$file" "$section" "$key" "$value"
      }

      windows_path() {
        local path="$1"
        local converted=""

        converted="$("${pkgs.wineWow64Packages.full}/bin/winepath" -w "$path" 2>/dev/null || true)"
        if [ -n "$converted" ]; then
          printf '%s\n' "$converted"
        else
          python3 -c 'import sys; print("Z:" + sys.argv[1].replace("/", "\\"))' "$path"
        fi
      }

      # IMM/Wine skin workaround:
      # The upstream "New Skin" can render list text as black blocks under Wine.
      # Use the "Original Skin" by default; set IMM_WINE_KEEP_NEW_SKIN=1 to opt out.
      if [ -f "$ini_file" ] && [ "''${IMM_WINE_KEEP_NEW_SKIN:-0}" != "1" ]; then
        orig_skin_dir="$app_dir/Skins_Folder/Original Skin"
        if [ -d "$orig_skin_dir" ]; then
          orig_skin_win_path="$(windows_path "$orig_skin_dir")"
          set_ini_value "$ini_file" "Folder" "Skin" "$orig_skin_win_path"
        fi

        # Improve label contrast in Original Skin so list/options text stays readable.
        skin_ini="$app_dir/Skins_Folder/Original Skin/Skin.ini"
        if [ -f "$skin_ini" ]; then
          set_ini_value "$skin_ini" "Colors" "FontColors" "#FFB420"
          set_ini_value "$skin_ini" "Colors" "UassetFontColors" "#D3E5AE"
          set_ini_value "$skin_ini" "Colors" "ButtonsFontColors" "#D3E5AE"
          set_ini_value "$skin_ini" "Colors" "ButtonsMouseOverFontColor" "#000000"
          set_ini_value "$skin_ini" "Colors" "ButtonsPressedFontColor" "#D3E5AE"
        fi
      fi

      # Keep IMM 4K UI mode disabled by default; enabling it can cause clipped
      # labels on Wine with some skins/desktop scales. Set IMM_WINE_KEEP_4KUI=1
      # to keep your existing setting.
      if [ -f "$ini_file" ] && [ "''${IMM_WINE_KEEP_4KUI:-0}" != "1" ]; then
        set_ini_value "$ini_file" "Settings" "4KUI" "false"
      fi

      # IMM rendering fix:
      # Force modern TrueType replacements so Wine does not render list text via
      # legacy bitmap families (MS Sans Serif/System/Fixedsys), which can appear
      # as blocky or unreadable glyphs on some setups.
      font_substitutions=(
        "MS Sans Serif|Tahoma"
        "MS Serif|Times New Roman"
        "System|Tahoma"
        "Fixedsys|Courier New"
        "Segoe UI|Tahoma"
        "MS Shell Dlg|Tahoma"
        "MS Shell Dlg 2|Tahoma"
      )

      for hive in \
        'HKCU\Software\Wine\Fonts\Replacements' \
        'HKLM\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes'
      do
        for pair in "''${font_substitutions[@]}"; do
          name="''${pair%%|*}"
          value="''${pair#*|}"
          "$wine_bin" reg add "$hive" /v "$name" /t REG_SZ /d "$value" /f >/dev/null 2>&1 || true
        done
      done

      # Additional font registry workaround:
      # Make MS Sans Serif resolve to Tahoma TTF to avoid Wine bitmap font usage.
      "$wine_bin" reg add \
        'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
        /v 'MS Sans Serif' /t REG_SZ /d 'tahoma.ttf' /f >/dev/null 2>&1 || true
      "$wine_bin" reg add \
        'HKLM\Software\Microsoft\Windows NT\CurrentVersion\Fonts' \
        /v 'MS Sans Serif Bold' /t REG_SZ /d 'tahomabd.ttf' /f >/dev/null 2>&1 || true

      # Keep WinForms layout stable under HiDPI desktop scaling.
      "$wine_bin" reg add \
        'HKCU\Control Panel\Desktop' \
        /v LogPixels /t REG_DWORD /d 96 /f >/dev/null 2>&1 || true
      "$wine_bin" reg add \
        'HKCU\Control Panel\Desktop' \
        /v Win8DpiScaling /t REG_DWORD /d 0 /f >/dev/null 2>&1 || true

      ${optionalString cfg.autoInstallDotnet80 ''
        if [ ! -f "$prefix/.dotnetdesktop8-installed" ]; then
          echo "Installing .NET Desktop Runtime 8 (dotnetdesktop8) into $prefix (requires network access)..."
          ${pkgs.winetricks}/bin/winetricks -q dotnetdesktop8
          touch "$prefix/.dotnetdesktop8-installed"
        fi
      ''}

      cd "$app_dir"
      exec "$wine_bin" "$app_dir/IcarusModManager.exe" "$@"
    '';
  };
in
{
  options.programs.icarusModManager = {
    enable = mkEnableOption "Icarus Mod Manager (Wine launcher)";

    version = mkOption {
      type = types.str;
      default = "2.4.0";
      description = "Upstream release version to download.";
    };

    source = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Override URL to the Standalone zip release. Defaults to the official GitHub asset for the configured version.";
    };

    hash = mkOption {
      type = types.str;
      default = "sha256-z4Ns76YtaWgCzUtvddOu7dWJdpCxTpywVoAxLDAynck=";
      description = "Hash of the downloaded archive (SRI format).";
    };

    winePrefix = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/.local/share/wineprefixes/icarus-mod-manager";
      description = "Wine prefix used to run Icarus Mod Manager.";
    };

    mutableDataDir = mkOption {
      type = types.str;
      default = defaultDataDir;
      description = "Writable directory where the manager is launched from. The packaged files are copied here on first run.";
    };

    autoInstallDotnet80 = mkOption {
      type = types.bool;
      default = false;
      description = "Automatically install the Windows .NET Desktop Runtime 8 (winetricks dotnetdesktop8) on first launch.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      launcher
      dataPackage
    ];

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
