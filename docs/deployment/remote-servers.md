## Remote server deployment playbook

Use this guide when a machine is booted into the stock NixOS installer (ISO,
PXE, kexec). The workflow is optimised for two classes of machines:

| Scope     | Managers that receive the private key | Secrets root                                           |
|-----------|---------------------------------------|--------------------------------------------------------|
| personal  | `tux-h4xx-01`, `tab-h4xx-02`, `lenovo-h4xx-03`, `lenovo-h4xx-04` | `secrets/profiles/personal/desktops/<manager>/ssh`     |
| work      | `macbook-pro`                         | `secrets/profiles/work/desktops/macbook-pro/ssh`       |

### 0. Prerequisites

- `nix` with flakes + the Age key material (see `modules/features/devops/sops-age`)
- `ssh`, `sops`, and [`nixos-anywhere`](https://github.com/nix-community/nixos-anywhere)
  (the wrapper script calls it via `nix run`)
- Reachability (wired LAN or console access) to the installer
- The host’s secrets directory under
  `secrets/profiles/<scope>/servers/<hostname>` – used to store bootstrap
  credentials and authorized keys

### 1. Generate a dedicated management key

Each server gets its own admin key pair so that private keys can be scoped per
managing workstation. Run this from the repo root:

```bash
scripts/servers/create-management-key.sh docker-host-01 dacoso
# or, for personal machines:
scripts/servers/create-management-key.sh my-homelab-node personal
```

What this does:

1. Generates an Ed25519 key pair under `tmp/`.
2. Encrypts the private key into the appropriate secret directories (based on
   `.sops.yaml` rules).
3. Stores the public key under `secrets/profiles/<scope>/servers/<hostname>/ssh/`.
4. Prints a ready-to-paste entry for `resources/ssh/hosts/personal.nix`.

Commit the resulting secret files (they are encrypted). On the managing
workstations you can decrypt/install the key with:

```bash
sops -d secrets/profiles/personal/desktops/tux-h4xx-01/ssh/<host>-personal-mgmt.priv > ~/.ssh/<host>-mgmt
chmod 600 ~/.ssh/<host>-mgmt
```

Update `resources/ssh/hosts/personal.nix` so Home Manager automatically wires the new
identity into `~/.ssh/config`.

### 2. Allow the ISO to trust the new key

While the target machine runs the NixOS installer, push the freshly generated
public key into `/root/.ssh/authorized_keys`:

```bash
host=docker-host-01
pub="secrets/profiles/work/servers/${host}/ssh/${host}-work-mgmt.pub"
scp "${pub}" root@<installer-ip>:/tmp/mgmt.pub
ssh root@<installer-ip> "mkdir -p /root/.ssh && cat /tmp/mgmt.pub >> /root/.ssh/authorized_keys"
```

Optionally set a temporary root password (`passwd`) so you have a fallback console login.

### 3. Fire the unattended install

Use the helper wrapper (it sets `--flake` and the target) while the ISO is up:

```bash
# Example: deploy docker-host-01 to 10.7.5.5
scripts/servers/deploy-from-iso.sh docker-host-01 root@10.7.5.5 \
  --identity ~/.ssh/docker-host-01-mgmt
```

Pass any additional nixos-anywhere flags (disk layout, extra-files, etc.) after
the `<target>` argument. The tool will:

1. Copy the flake to the installer environment
2. Partition + format disks via `disko` (if the host module imports it)
3. Build the target configuration (`nixosConfigurations.<host>`)
4. Activate the system and reboot into it

`deploy-from-iso.sh` defaults to `--phases disko,install,reboot` (no kexec), which avoids
DHCP/IP churn on machines already running a NixOS installer. If you intentionally want
the kexec phase, add `--with-kexec`.

### 4. Bootstrap secrets + comin

After the machine reboots into the freshly installed system:

1. `ssh ${host}` using the management key you just installed (entries come from
   `resources/ssh/hosts/personal.nix`)
2. `sudo ln -s /run/secrets /var/lib/sops` if the host consumes additional
   secrets during first boot (for dacoso hosts see `dacoso.server` module)
3. Verify that comin pulled the latest generation:
   ```bash
   sudo systemctl status comin.service
   sudo journalctl -u comin.service -n 50
   ```
   By default it polls the `develop` branch on GitHub every minute.

### 5. Updating SSH configs for operators

All host-specific SSH match blocks live in `resources/ssh/hosts/personal.nix` (personal)
and `resources/ssh/hosts/dacoso.nix` (work). Each entry defines the alias, user,
and which identity to use (`personal` or `work`). Once you add/adjust a host:

If this repository is public, keep private IPs out of git by putting the real
`HostName` mappings into the per-profile SOPS secret `ssh/hostnames-private.conf`
(decrypted to `~/.ssh/config.d/15-hostnames-private`).

1. Commit the change
2. Run `home-manager switch` (or rebuild the desktop NixOS configuration)
3. Optionally re-run the key-generation script if a new management key is needed

### 6. Troubleshooting tips

- Use `scripts/servers/deploy-from-iso.sh ... --keep-booted --debug` to keep the
  installer around for inspection
- The comin service writes `/var/lib/comin/comin.yaml`; inspect it to ensure the
  correct hostname/flake output is targeted
- For private repositories, configure `services.comin.remotes.[].auth.access_token_path`
  (store the token via `sops-nix`) inside host modules
