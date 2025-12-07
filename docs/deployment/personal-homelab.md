## Personal homelab server template

This flow reuses `hosts/homelab/_template` to spin up a new personal node with
DHCP networking, Europe/Berlin timezone, and console bootstrap passwords (hash
of `ChangeMeNow!` for both `root` and `nixos`; SSH password auth stays disabled
unless you flip `usePasswordAuth`).

1. Boot the stock NixOS installer and set console passwords
   ```bash
   passwd root
   passwd nixos
   ```
2. Create the host from the template and fill in its identity
   ```bash
   host=YOURSHORT
   cp -r hosts/homelab/_template "hosts/homelab/${host}"
   $EDITOR hosts/homelab/${host}/configuration.nix
   # set networking.hostName/domain, managementPubKey ("ssh/${host}-personal-mgmt.pub"), extraHosts hint
   ```
   Replace `hardware-configuration.nix` with the generated one from the installer:
   ```bash
   ssh root@<installer-ip> nixos-generate-config --show-hardware-config > "hosts/homelab/${host}/hardware-configuration.nix"
   ```
3. Generate the per-host SSH key (lives under `secrets/profiles/personal/desktops/common/ssh/`)
   ```bash
   scripts/servers/create-management-key.sh "${host}" personal
   ```
   This writes `<host>-personal-mgmt.{priv,pub}` encrypted via `.sops.yaml`.
4. Wire the key into your personal desktops so the right identity is used automatically
   - Add the key to `resources/ssh/keys.nix`:
     ```nix
     { secret = "ssh/${host}-personal-mgmt.priv"; path = ".ssh/personal/${host}-personal-mgmt"; }
     ```
   - Add a host entry to `resources/ssh/hosts.nix` (the new `keyName` field expands to `~/.ssh/personal/<name>`):
     ```nix
     {
       match = "${host}";
       alias = "${host}";
       hostName = "${host}.your.domain";
       user = "root";
       keyName = "${host}-personal-mgmt";
     }
     ```
   - Rebuild Home Manager / desktop NixOS so the config and key get installed.
5. Hook the host into the flake
   - Add a `secretsByProfile` entry for `${host}` in `flake.nix` pointing at `secrets/profiles/personal/servers/${host}` (mirror the shape used for `srv4`):
     ```nix
     ${host} = {
       primary = personalServerRoot "${host}";
       shared = sharedCommonRoot;
       profileShared = personalSharedRoot;
       profileCommon = personalCommonDesktopRoot;
       root = personalServerRoot "${host}";
       personal = personalServerRoot "${host}";
     };
     ```
   - Add a nixosConfiguration using `personalHomelabServerModules`:
     ```nix
     ${host} = mkNixosHost "${host}" (
       personalHomelabServerModules ++ [
         ./hosts/homelab/${host}/configuration.nix
       ]
     );
     ```
6. Deploy from the installer with nixos-anywhere
   ```bash
   scripts/servers/deploy-from-iso.sh "${host}" root@<installer-ip>
   ```
7. After the first boot, change the default password and confirm the management
   key works:
   ```bash
   ssh ${host}   # uses ~/.ssh/personal/${host}-personal-mgmt
   sudo passwd root
   sudo passwd nixos
   ```

### Age keys per host?

You only need a per-host Age key if the machine itself must decrypt SOPS secrets
at runtime (beyond the installer/build machine). If you keep secrets decryption
on your desktops while building images (e.g. nixos-anywhere) and only ship
plaintext outputs into the system, you can skip adding another Age recipient.
If you do add one: generate with `age-keygen`, store under
`secrets/profiles/personal/servers/${host}/age.key`, and extend `.sops.yaml`
with that recipient.

### Full disk encryption + remote unlock

- Define the LUKS device in the host configuration (replace the UUID):
  ```nix
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/<root-luks-uuid>";
    allowDiscards = true;
  };
  ```
- Enable SSH in initramfs for remote unlock (port 2222, authorized key must be
  plaintext at build time—use the decrypted management pubkey):
  ```nix
  boot.initrd.network = {
    enable = true;
    ssh = {
      enable = true;
      port = 2222;
      authorizedKeys = [ "ssh-ed25519 AAAA... ${host}-personal-mgmt" ];
      generateHostKeys = true;
    };
  };
  ```
- Add an unlock entry to `resources/ssh/hosts.nix` so you can target the
  initramfs SSH listener:
  ```nix
  {
    match = "unlock-${host}";
    alias = "unlock-${host}";
    hostName = "${host}.your.domain"; # or IP used during boot
    port = 2222;
    user = "root";
    keyName = "${host}-personal-mgmt";
  }
  ```
- Store the LUKS passphrase in personal shared secrets, e.g.
  `secrets/profiles/personal/shared/luks/${host}.txt` (encrypted via SOPS).
  To unlock from your desktop:
  ```bash
  pass=$(sops -d secrets/profiles/personal/shared/luks/${host}.txt)
  ssh unlock-${host} "echo -n \"$pass\" | cryptsetup open /dev/disk/by-uuid/<root-luks-uuid> cryptroot"
  ```
  (Adjust the device/mapper name to your layout.) The target does not need an
  Age key for this; only the desktop needs it to decrypt the passphrase.
