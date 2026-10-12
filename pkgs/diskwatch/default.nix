# diskwatch: read-only disk-diagnostics TUI (devices, volumes, filesystems,
# IO-latency histogram, SMART health). Not yet in our pinned nixpkgs; drop this
# package once nixpkgs catches up (upstream advertises `nix-shell -p diskwatch`).
# SMART reads need root (run `sudo diskwatch`); pair with smartmontools for the
# full attribute tables.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "diskwatch";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "matthart1983";
    repo = "diskwatch";
    tag = "v${finalAttrs.version}";
    hash = "sha256-qSPTnOYiaY1vcFoGaNppgjmwLbl03kQMvNUgbFP5eWw=";
  };

  cargoHash = "sha256-Xaq49j2JhrcqCY7bLiIf6yKC99Je5WwSgzV/vk1VsZU=";

  meta = {
    description = "Read-only single-host disk diagnostics TUI (IO latency + SMART in one view)";
    homepage = "https://github.com/matthart1983/diskwatch";
    changelog = "https://github.com/matthart1983/diskwatch/releases/tag/${finalAttrs.src.tag}";
    platforms = lib.platforms.linux;
    license = lib.licenses.mit;
    mainProgram = "diskwatch";
  };
})
