{
  defaults = import ./defaults.nix;
  personalHosts = import ./hosts/personal.nix;
  workHosts = import ./hosts/work.nix;
}
