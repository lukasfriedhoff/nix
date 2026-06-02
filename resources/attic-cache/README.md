# Attic cache resources

Add `homelab.pub` here after bootstrapping `srv3` Attic with:

```bash
attic cache info srv3:homelab
```

Once `resources/attic-cache/homelab.pub` exists, clients automatically prefer
Attic over the legacy `nix-serve` cache via `hosts/common/default.nix`.
