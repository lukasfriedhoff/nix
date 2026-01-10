# Gaming tools: mod managers, game-specific utilities
# Note: icarus (game server) is a NixOS module, not home-manager.
# It should be imported via modules/nixos/services/ if needed.
{
  imports = [
    ./icarus-mod-manager
  ];
}
