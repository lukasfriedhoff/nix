# tsuzuri: block-based Markdown notebook TUI (notes stay plain .md files).
# Built from the lukasfriedhoff fork of jaisuriya-11/tsuzuri; pinned to a commit
# because the fork carries no release tags. Consumed by
# modules/features/profile/desktop/home.nix.
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule (finalAttrs: {
  pname = "tsuzuri";
  version = "0.2.0-unstable-2026-10-05";

  src = fetchFromGitHub {
    owner = "lukasfriedhoff";
    repo = "tsuzuri";
    rev = "67bbab7cacef49a31628842658a1771782f65d9e";
    hash = "sha256-i9EM2Tsjnja/e+7SAmL7oyUoWl+5wDpkTD6jgLUx5uk=";
  };

  vendorHash = "sha256-Al9YpToJRYq71aupVq+mn8yYSb1GefHZcz3Dz+mCgVU=";

  subPackages = [ "cmd/tsuzuri" ];

  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${finalAttrs.version}"
  ];

  meta = {
    description = "Block-based Markdown notebook for the terminal";
    homepage = "https://github.com/lukasfriedhoff/tsuzuri";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
    mainProgram = "tsuzuri";
  };
})
