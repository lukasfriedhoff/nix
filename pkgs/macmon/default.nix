# macmon 0.8.x: nixpkgs still ships 0.6.1, which panics on the M5 Max
# (renumbered voltage-states keys; vladkens/macmon#47). Drop this package
# once nixpkgs catches up.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "macmon";
  version = "0.8.2";

  src = fetchFromGitHub {
    owner = "vladkens";
    repo = "macmon";
    tag = "v${finalAttrs.version}";
    hash = "sha256-tdWuxpV+AAN189etks6LVo4OYDYQNd9dzfopECFgoR8=";
  };

  cargoHash = "sha256-U71Qrplz2CY5CiYpDjFrtWQOy1J4HE3tMhnRbLXUD7k=";

  meta = {
    description = "Sudoless performance monitoring for Apple Silicon processors";
    homepage = "https://github.com/vladkens/macmon";
    changelog = "https://github.com/vladkens/macmon/releases/tag/${finalAttrs.src.tag}";
    platforms = [ "aarch64-darwin" ];
    license = lib.licenses.mit;
    mainProgram = "macmon";
  };
})
