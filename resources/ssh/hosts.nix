{
  defaults = import ./defaults.nix;
  personalHosts = import ./hosts/personal.nix;
  dacosoHosts = import ./hosts/dacoso.nix;
}
