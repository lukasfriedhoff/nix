{
  buildNpmPackage,
  fetchurl,
  runCommand,
  selkiesSrc,
  selkiesVersion,
}:

# The HTML5 client the selkies wheel ships as package data. Upstream builds it
# with scripts/ci/build-web.sh (node); this reproduces that script's shipping
# output: web-core bundled into the classic dashboard, plus the touch-gamepad
# shim and the PWA files. The Wish dashboard is upstream-CI-only and skipped.
let
  # gendb.js downloads the SDL controller DB at build time and silently skips
  # gamepad remapping when offline (as in the sandbox); pin the DB instead.
  gamecontrollerdb = fetchurl {
    url = "https://raw.githubusercontent.com/mdqinc/SDL_GameControllerDB/5a12daa568d19344f9b6e9286ef5929833b25c7c/gamecontrollerdb.txt";
    hash = "sha256-B+xbdT5oXEgpmHkZsnkFzDxFyOGMEbMEbidfzziw88s=";
  };

  core = buildNpmPackage {
    pname = "selkies-web-core";
    version = selkiesVersion;
    src = selkiesSrc;
    sourceRoot = "${selkiesSrc.name}/addons/selkies-web-core";
    npmDepsHash = "sha256-reZYWs1KNqBGnMX95PZW6B/epaarA7poq9F/nrtJv70=";

    # fetch(DB_URL) -> the pinned file, keeping gendb's parsing/conversion.
    postPatch = ''
      substituteInPlace gendb.js \
        --replace-fail "await fetch(DB_URL)" \
          "new Response(fs.readFileSync('${gamecontrollerdb}', 'utf8'))"
    '';

    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };

  dashboard = buildNpmPackage {
    pname = "selkies-dashboard";
    version = selkiesVersion;
    src = selkiesSrc;
    sourceRoot = "${selkiesSrc.name}/addons/selkies-dashboard";
    npmDepsHash = "sha256-jdXhb9dr7nn3PuMB43yWb+8AKlzm7pelGmRn7i/8bs4=";

    # copy-core.js (prebuild) and copy-jsdb.js (postbuild) expect the core's
    # dist at ../selkies-web-core/dist, exactly where the repo checkout has
    # the source; provide the built output there.
    preBuild = ''
      # unpackPhase only makes sourceRoot writable, not the sibling core dir.
      chmod -R u+w ../selkies-web-core
      cp -r ${core} ../selkies-web-core/dist
      chmod -R u+w ../selkies-web-core/dist
    '';

    env.SELKIES_INJECT = "1";

    installPhase = ''
      runHook preInstall
      cp -r dist $out
      runHook postInstall
    '';
  };
in
# Assembly mirrors the tail of build-web.sh.
runCommand "selkies-web-${selkiesVersion}" { } ''
  cp -r ${dashboard} $out
  chmod -R u+w $out
  mkdir -p $out/src
  cp ${core}/selkies-core.js $out/src/
  cp ${selkiesSrc}/addons/universal-touch-gamepad/universalTouchGamepad.js $out/src/

  echo '"""Bundled web client, served by the stream server as package data."""' \
    > $out/__init__.py
  printf '%s' '{"name":"Selkies","short_name":"Selkies","display":"fullscreen","background_color":"#000000","theme_color":"#000000","icons":[{"src":"icon-512.png","type":"image/png","sizes":"512x512"}],"start_url":"."}' \
    > $out/manifest.json
  cp ${selkiesSrc}/docs/assets/logo/icon-512x512.png $out/icon-512.png
  cp ${selkiesSrc}/docs/assets/logo/favicon.ico $out/favicon.ico

  test -f $out/index.html
''
