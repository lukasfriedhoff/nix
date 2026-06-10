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

  baseVersionUnderscored = lib.replaceStrings [ "." ] [ "_" ] cfg.baseVersion;

  sourceUrl =
    if cfg.source != null then
      cfg.source
    else
      "https://github.com/Jimk72/Icarus_Software/raw/main/Icarus_Mod_Manager_${baseVersionUnderscored}.zip";

  dataPackage = pkgs.stdenvNoCC.mkDerivation {
    pname = "icarus-mod-manager-data";
    inherit (cfg) version;

    src = pkgs.fetchzip {
      url = sourceUrl;
      stripRoot = false;
      inherit (cfg) hash;
    };

    patchZip = lib.optionalString (cfg.patchSource != null) (
      pkgs.fetchzip {
        url = cfg.patchSource;
        stripRoot = false;
        hash = cfg.patchHash;
      }
    );

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/icarus-mod-manager"
      cp -R . "$out/share/icarus-mod-manager"
      if [ -n "$patchZip" ]; then
        cp -R --no-preserve=mode,ownership "$patchZip/." "$out/share/icarus-mod-manager/"
      fi
      runHook postInstall
    '';
  };

  unrealPakPackage = pkgs.fetchzip {
    url = "https://github.com/Jimk72/Icarus_Software/raw/main/UnrealPak.zip";
    stripRoot = false;
    hash = "sha256-1NovjtmDQsKvFAEOHCgy7c1qvLsX0TQp/uqEcqSd+V4=";
  };

  dataArchivePackage = pkgs.fetchzip {
    url = "https://github.com/Jimk72/Icarus_Software/raw/main/data.zip";
    stripRoot = false;
    hash = "sha256-twjpwf9J6EAq4uZqKz/UFjng0rW1bsURGg/IoMBu30Y=";
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
      configured_content_dir="${cfg.icarusContentDir}"
      unreal_pak_dir="$app_dir/UnrealPak"
      unreal_pak_exe="$unreal_pak_dir/Engine/Binaries/Win64/UnrealPak.exe"

      export WINEPREFIX="$prefix"
      export WINEDEBUG="''${WINEDEBUG:--all}"
      export WINEDLLOVERRIDES="mscoree=d,mshtml=d,winewayland.drv=d,''${WINEDLLOVERRIDES:-}"
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

      json_valid() {
        python3 - "$1" <<'PY'
      import json
      import sys

      try:
          with open(sys.argv[1], encoding="utf-8") as handle:
              json.load(handle)
      except Exception:
          sys.exit(1)
      PY
      }

      database_stale() {
        local path="$1"
        local max_age_seconds="$2"

        if [ ! -f "$path" ] || ! json_valid "$path"; then
          return 0
        fi

        local now modified
        now="$(date +%s)"
        modified="$(stat -c %Y "$path" 2>/dev/null || echo 0)"
        [ $((now - modified)) -gt "$max_age_seconds" ]
      }

      repair_json_file() {
        local path="$1"

        if [ ! -f "$path" ] || json_valid "$path"; then
          return
        fi

        local backup
        backup="$path.corrupt.$(date +%s)"
        progress "backing up corrupt $(basename "$path") to $(basename "$backup")"
        mv "$path" "$backup"
      }

      update_database_files() {
        local repos_path="$app_dir/repos.json"
        local mods_path="$app_dir/mods.json"
        local repos_tmp="$app_dir/repos.json.tmp"
        local mods_tmp="$app_dir/mods.json.tmp"

        repair_json_file "$repos_path"
        repair_json_file "$mods_path"

        progress "fetching Icarus Mod Manager database"
        if python3 - "$repos_tmp" "$mods_tmp" <<'PY'
      import json
      import sys
      import urllib.parse
      import urllib.request

      repos_path = sys.argv[1]
      mods_path = sys.argv[2]
      base = "https://firestore.googleapis.com/v1/projects/projectdaedalus-fb09f/databases/(default)/documents"

      def fetch_json(url):
          with urllib.request.urlopen(url, timeout=30) as response:
              return json.loads(response.read().decode("utf-8"))

      repos = fetch_json(f"{base}/meta/repos?pageSize=300")

      documents = []
      page_token = None
      while True:
          query = {"pageSize": "300"}
          if page_token:
              query["pageToken"] = page_token
          url = f"{base}/mods?{urllib.parse.urlencode(query)}"
          page = fetch_json(url)
          documents.extend(page.get("documents", []))
          page_token = page.get("nextPageToken")
          if not page_token:
              break

      with open(repos_path, "w", encoding="utf-8") as handle:
          json.dump(repos, handle, ensure_ascii=False, separators=(",", ":"))
          handle.write("\n")
      with open(mods_path, "w", encoding="utf-8") as handle:
          json.dump({"documents": documents}, handle, ensure_ascii=False, separators=(",", ":"))
          handle.write("\n")
      PY
        then
          if json_valid "$repos_tmp" && json_valid "$mods_tmp"; then
            mv "$repos_tmp" "$repos_path"
            mv "$mods_tmp" "$mods_path"
            progress "Icarus Mod Manager database refreshed"
            return
          fi
        fi

        rm -f "$repos_tmp" "$mods_tmp"
        if [ ! -f "$repos_path" ] || [ ! -f "$mods_path" ]; then
          echo "Warning: could not refresh Icarus Mod Manager database; the in-app Update Database button is known to hang under Wine." >&2
        else
          echo "Warning: using existing Icarus Mod Manager database; refresh failed." >&2
        fi
      }

      download_mod() {
        local query="''${1:-}"
        if [ -z "$query" ]; then
          echo "Usage: icarus-mod-manager --download-mod <mod name>" >&2
          return 2
        fi

        repair_database_files

        python3 - "$app_dir" "$query" <<'PY'
      import json
      import shutil
      import sys
      import tempfile
      import urllib.parse
      import urllib.request
      import zipfile
      from pathlib import Path

      app_dir = Path(sys.argv[1])
      query = sys.argv[2].strip()
      mods_path = app_dir / "mods.json"
      downloads_dir = app_dir / "Downloaded_Mods"

      def string_value(value):
          if isinstance(value, dict):
              return value.get("stringValue") or ""
          return ""

      def normalize_url(url):
          parsed = urllib.parse.urlsplit(url)
          path = urllib.parse.quote(urllib.parse.unquote(parsed.path), safe="/%")
          query = urllib.parse.quote(urllib.parse.unquote(parsed.query), safe="=&%")
          return urllib.parse.urlunsplit((parsed.scheme, parsed.netloc, path, query, parsed.fragment))

      def safe_extract(archive, destination):
          destination = destination.resolve()
          for member in archive.infolist():
              target = (destination / member.filename).resolve()
              if destination != target and destination not in target.parents:
                  raise RuntimeError(f"Refusing unsafe archive member: {member.filename}")
          archive.extractall(destination)

      def merge_tree(source, destination):
          if not source.exists():
              return
          destination.mkdir(parents=True, exist_ok=True)
          for child in source.iterdir():
              target = destination / child.name
              if child.is_dir():
                  merge_tree(child, target)
              else:
                  target.parent.mkdir(parents=True, exist_ok=True)
                  shutil.copy2(child, target)

      with mods_path.open(encoding="utf-8") as handle:
          documents = json.load(handle).get("documents", [])

      mods = []
      for document in documents:
          fields = document.get("fields", {})
          files = fields.get("files", {}).get("mapValue", {}).get("fields", {})
          urls = {name: string_value(value) for name, value in files.items() if string_value(value)}
          if not urls:
              continue
          name = string_value(fields.get("name"))
          author = string_value(fields.get("author"))
          compatibility = string_value(fields.get("compatibility"))
          version = string_value(fields.get("version"))
          mods.append(
              {
                  "name": name,
                  "author": author,
                  "compatibility": compatibility,
                  "version": version,
                  "urls": urls,
              }
          )

      query_lower = query.lower()
      exact = [
          mod
          for mod in mods
          if mod["name"].lower() == query_lower
          or f'{mod["author"]}:{mod["name"]}'.lower() == query_lower
      ]
      matches = exact or [mod for mod in mods if query_lower in mod["name"].lower()]

      if not matches:
          raise SystemExit(f"No mod found matching: {query}")
      if len(matches) > 1:
          print(f"Multiple mods match {query!r}; use the exact mod name:", file=sys.stderr)
          for mod in matches[:25]:
              print(f'  - {mod["name"]} ({mod["author"]}, {mod["compatibility"]})', file=sys.stderr)
          raise SystemExit(2)

      mod = matches[0]
      url_kind = "exmodz" if "exmodz" in mod["urls"] else "pak" if "pak" in mod["urls"] else next(iter(mod["urls"]))
      url = normalize_url(mod["urls"][url_kind])
      filename = Path(urllib.parse.unquote(urllib.parse.urlsplit(url).path)).name or f'{mod["name"]}.{url_kind}'
      downloads_dir.mkdir(parents=True, exist_ok=True)
      output_path = downloads_dir / filename
      for stale_path in downloads_dir.glob(f".{filename}.*"):
          stale_path.unlink(missing_ok=True)

      request = urllib.request.Request(url, headers={"User-Agent": "icarus-mod-manager-nix-wrapper"})
      with tempfile.NamedTemporaryFile(prefix=f".{filename}.", dir=downloads_dir, delete=False) as tmp:
          tmp_path = Path(tmp.name)
          try:
              with urllib.request.urlopen(request, timeout=120) as response:
                  shutil.copyfileobj(response, tmp)
          except Exception:
              tmp_path.unlink(missing_ok=True)
              raise
      tmp_path.replace(output_path)

      print(f'Downloaded {mod["name"]} {mod["version"]} from {url}')
      print(f"Saved {output_path}")

      if url_kind.lower() == "exmodz" or zipfile.is_zipfile(output_path):
          with zipfile.ZipFile(output_path) as archive:
              safe_extract(archive, app_dir)
          merge_tree(app_dir / "Extracted Mods", app_dir / "Extracted_Mods")
          print(f"Extracted {output_path.name} into {app_dir}")
      else:
          print("Downloaded a PAK file only; import/install it through Icarus Mod Manager.")
      PY
      }

      repair_database_files() {
        if database_stale "$app_dir/repos.json" 86400 || database_stale "$app_dir/mods.json" 86400; then
          update_database_files
          return
        fi

        repair_json_file "$app_dir/repos.json"
        repair_json_file "$app_dir/mods.json"
      }

      configure_app_files() {
        if [ "''${IMM_SKIP_FIRST_RUN_BOOTSTRAP:-0}" != "1" ]; then
          install_unreal_pak
          preseed_first_run_settings
        fi

        repair_database_files

        local orig_skin_dir="$app_dir/Skins_Folder/Original Skin"
        if [ -d "$orig_skin_dir" ]; then
          set_ini_value "$ini_file" Folder Skin "$(windows_path "$orig_skin_dir")"
        fi

        local skin_ini="$orig_skin_dir/Skin.ini"
        if [ "''${IMM_WINE_KEEP_NEW_SKIN:-0}" != "1" ]; then
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

      install_unreal_pak() {
        if [ -f "$unreal_pak_exe" ]; then
          progress "UnrealPak already installed"
          return
        fi

        progress "installing UnrealPak"
        mkdir -p "$unreal_pak_dir"
        cp -R --no-preserve=mode,ownership "${unrealPakPackage}/UnrealPak/." "$unreal_pak_dir/"
      }

      install_data_archive() {
        if [ -d "$app_dir/data" ] && find "$app_dir/data" -type f -name '*.json' -print -quit | grep -q .; then
          progress "Icarus data archive already installed"
          return
        fi

        progress "installing bundled Icarus data archive"
        rm -rf "$app_dir/data"
        cp -R --no-preserve=mode,ownership "${dataArchivePackage}/data" "$app_dir/data"
      }

      find_icarus_content_dir() {
        if [ -n "$configured_content_dir" ]; then
          if [ -d "$configured_content_dir" ]; then
            printf '%s\n' "$configured_content_dir"
            return
          fi
          echo "Warning: configured Icarus content directory does not exist: $configured_content_dir" >&2
        fi

        local candidate
        for candidate in \
          "$HOME/media/SteamLibrary/steamapps/common/Icarus/Icarus/Content" \
          "$HOME/.local/share/Steam/steamapps/common/Icarus/Icarus/Content" \
          "$HOME/.steam/steam/steamapps/common/Icarus/Icarus/Content" \
          "$HOME/.steam/root/steamapps/common/Icarus/Icarus/Content" \
          "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/common/Icarus/Icarus/Content"
        do
          if [ -d "$candidate" ]; then
            printf '%s\n' "$candidate"
            return
          fi
        done
      }

      preseed_first_run_settings() {
        local content_dir
        content_dir="$(find_icarus_content_dir)"

        install_data_archive
        set_ini_value "$ini_file" App Left 0
        set_ini_value "$ini_file" App Top 0
        set_ini_value "$ini_file" Folder IMM "$(windows_path "$app_dir")\\"
        set_ini_value "$ini_file" File UE4PakEXE "$(windows_path "$unreal_pak_exe")"
        set_ini_value "$ini_file" Settings AltDownloader true
        set_ini_value "$ini_file" Settings LocalFolder true

        if [ -n "$content_dir" ]; then
          set_ini_value "$ini_file" Folder IcarusContent "$(windows_path "$content_dir")"
        else
          echo "Warning: could not auto-detect the Icarus content directory; set programs.icarusModManager.icarusContentDir." >&2
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
        --update-db)
          update_database_files
          ;;
        --download-mod)
          shift
          download_mod "$*"
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
      default = "2.4.7";
      description = "Upstream release version to download.";
    };

    baseVersion = mkOption {
      type = types.str;
      default = "2.4.0";
      description = "Base standalone zip version used before applying the optional patch archive.";
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

    patchSource = mkOption {
      type = types.nullOr types.str;
      default = "https://github.com/Jimk72/Icarus-Mod-Manager-Beta/raw/main/IcarusModManagerPATCH247.zip";
      description = "Optional upstream patch zip overlaid onto the standalone release.";
    };

    patchHash = mkOption {
      type = types.str;
      default = "sha256-p9puDr1/AhMXDGIfnq+ph7DwV3unSf/ZoR8UmAl7FUI=";
      description = "Hash of the optional patch archive in SRI format.";
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

    icarusContentDir = mkOption {
      type = types.str;
      default = "";
      description = "Optional native Linux path to the Icarus game Content directory. If empty, the launcher tries common Steam library paths.";
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
