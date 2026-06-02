{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  electron,
  findutils,
  git,
  makeWrapper,
  nodejs_22,
  pkg-config,
  python3,
  stdenv,
  systemd,
}:

let
  nodeBleUrl = "https://github.com/tuxedoxt/node-ble/archive/4b7cb1cbf62196894d9e15ef47dbb4821b63ec78.tar.gz";
  nodeBleIntegrity = "sha512-UAT5vSHHwrKLI5+ZIN+pRRkNu3zshfBH9NyUidgCtRLGAkDpfPKehIvKlgv2iyk2QMMpJwUN38ZSIO86FNIg3Q==";
  nodeDbusUrl = "https://github.com/tuxedoxt/node-dbus-next/archive/e875f304780e0d8108dbe1d7e7bdcf6ba9e9313f.tar.gz";
  nodeDbusIntegrity = "sha512-ectZNw/EG1PBVJaisDTdz3t8nEqVO0K9y7wQRyeBZdInvc0dfV2/plHGf8fj3w6xSlcP3NWNC3/3TMjqFZcIBg==";
in
buildNpmPackage rec {
  pname = "tuxedo-control-center";
  version = "2.1.22";

  src = fetchFromGitHub {
    owner = "tuxedocomputers";
    repo = "tuxedo-control-center";
    rev = "v${version}";
    hash = "sha256-W4890yTlMJaaC4g4Dmbj6mQHJTJLlB9z9OTxYj4TnhY=";
  };

  npmDepsHash = "sha256-Hp7x+ojs0xE3hGp9qcGM1dqJ1xLLx/yYv7U1AZQCbrU=";
  nodejs = nodejs_22;
  npmBuildScript = "build-prod";

  makeCacheWritable = true;
  npmFlags = [ "--legacy-peer-deps" ];
  npmRebuildFlags = [ "--ignore-scripts" ];

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    NODE_OPTIONS = "--openssl-legacy-provider";
  };

  nativeBuildInputs = [
    findutils
    git
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    systemd
    systemd.dev
  ];

  postPatch = ''
        substituteInPlace package.json \
          --replace "git+https://github.com/tuxedoxt/node-ble.git#match-and-event-leak-fixes-v2" "${nodeBleUrl}" \
          --replace "git+https://github.com/tuxedoxt/node-dbus-next.git#match-count-logic-fix" "${nodeDbusUrl}"

        ${python3}/bin/python3 - <<'PY'
    import json
    from pathlib import Path

    lock = Path("package-lock.json")
    data = json.loads(lock.read_text())

    node_ble_git = {
        "git+https://github.com/tuxedoxt/node-ble.git#match-and-event-leak-fixes-v2",
        "git+https://github.com/tuxedoxt/node-ble.git#4b7cb1cbf62196894d9e15ef47dbb4821b63ec78",
    }
    node_dbus_git = {
        "git+https://github.com/tuxedoxt/node-dbus-next.git#match-count-logic-fix",
        "git+https://github.com/tuxedoxt/node-dbus-next.git#e875f304780e0d8108dbe1d7e7bdcf6ba9e9313f",
    }

    node_ble_url = "${nodeBleUrl}"
    node_ble_integrity = "${nodeBleIntegrity}"
    node_dbus_url = "${nodeDbusUrl}"
    node_dbus_integrity = "${nodeDbusIntegrity}"

    def patch_dep(dep):
        version = dep.get("version")
        if version in node_ble_git:
            dep["version"] = node_ble_url
            dep["resolved"] = node_ble_url
            dep["integrity"] = node_ble_integrity
            if "from" in dep:
                dep["from"] = node_ble_url
        elif version in node_dbus_git:
            dep["version"] = node_dbus_url
            dep["resolved"] = node_dbus_url
            dep["integrity"] = node_dbus_integrity
            if "from" in dep:
                dep["from"] = node_dbus_url

        requires = dep.get("requires")
        if isinstance(requires, dict):
            for key, value in list(requires.items()):
                if value in node_ble_git:
                    requires[key] = node_ble_url
                elif value in node_dbus_git:
                    requires[key] = node_dbus_url

        for child in dep.get("dependencies", {}).values():
            patch_dep(child)

    for dep in data.get("dependencies", {}).values():
        patch_dep(dep)

    lock.write_text(json.dumps(data, indent=2, sort_keys=False))
    PY

        substituteInPlace package.json \
          --replace \
            "pkg --target node14-linux-x64 --output ./dist/tuxedo-control-center/data/service/tccd ./dist/tuxedo-control-center/service-app/package.json" \
            "true"

        substituteInPlace src/udev/99-webcam.rules \
          --replace "/usr/bin/python3" "${python3}/bin/python3"

        substituteInPlace src/dist-data/tuxedo-control-center.desktop \
          --replace 'Exec="/opt/tuxedo-control-center/tuxedo-control-center" %U' 'Exec=tuxedo-control-center %U' \
          --replace 'Icon=/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/dist-data/tuxedo-control-center_256.svg' \
            'Icon=tuxedo-control-center'

        substituteInPlace src/dist-data/tuxedo-control-center-tray.desktop \
          --replace 'Exec=/opt/tuxedo-control-center/tuxedo-control-center --tray' \
            'Exec=tuxedo-control-center --tray'

        substituteInPlace src/native-lib/tuxedo_io_napi.cc \
          --replace 'tdpInfo.Set("descriptor", tdpDescriptors.at(i));' \
            'tdpInfo.Set("descriptor", i < static_cast<int>(tdpDescriptors.size()) ? tdpDescriptors[i] : std::string());'
  '';

  doCheck = false;

  installPhase = ''
        runHook preInstall

        install -d $out/opt/tuxedo-control-center/resources/dist
        cp -R dist/tuxedo-control-center $out/opt/tuxedo-control-center/resources/dist/

        npm prune --omit=dev --no-save
        find node_modules -xtype l -delete
        cp -R node_modules $out/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/

        install -d $out/opt/tuxedo-control-center
        makeWrapper ${electron}/bin/electron $out/opt/tuxedo-control-center/tuxedo-control-center \
          --add-flags "$out/opt/tuxedo-control-center/resources/dist/tuxedo-control-center"

        install -d $out/bin
        ln -s $out/opt/tuxedo-control-center/tuxedo-control-center $out/bin/tuxedo-control-center

        install -d $out/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/service
        cat > $out/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/service/tccd <<EOF
    #!${stdenv.shell}
    exec ${nodejs}/bin/node --enable-source-maps "$out/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/service-app/service-app/main.js" "\$@"
    EOF
        chmod +x $out/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/service/tccd
        ln -s $out/opt/tuxedo-control-center/resources/dist/tuxedo-control-center/data/service/tccd $out/bin/tccd

        install -Dm444 src/dist-data/com.tuxedocomputers.tccd.conf \
          $out/share/dbus-1/system.d/com.tuxedocomputers.tccd.conf
        install -Dm444 src/dist-data/com.tuxedocomputers.tccd.policy \
          $out/share/polkit-1/actions/com.tuxedocomputers.tccd.policy
        install -Dm444 src/udev/99-webcam.rules \
          $out/lib/udev/rules.d/99-webcam.rules
        install -Dm444 src/dist-data/tuxedo-control-center.desktop \
          $out/share/applications/tuxedo-control-center.desktop
        install -Dm444 src/dist-data/tuxedo-control-center-tray.desktop \
          $out/share/applications/tuxedo-control-center-tray.desktop
        install -Dm444 src/dist-data/tuxedo-control-center_256.png \
          $out/share/icons/hicolor/256x256/apps/tuxedo-control-center.png
        install -Dm444 src/dist-data/com.tuxedocomputers.tcc.metainfo.xml \
          $out/share/metainfo/com.tuxedocomputers.tcc.metainfo.xml

        runHook postInstall
  '';

  meta = with lib; {
    description = "TUXEDO Control Center (GUI and daemon)";
    homepage = "https://github.com/tuxedocomputers/tuxedo-control-center";
    license = licenses.gpl3Only;
    platforms = platforms.linux;
    mainProgram = "tuxedo-control-center";
  };
}
