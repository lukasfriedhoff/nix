# Staging Cluster Plan (3-VM HA Copy of Testing)

This runbook defines exactly how to build a new **staging** k3s cluster as a copy of `testing-srv3`, using:

- `srv5-k3s-stg1`
- `srv6-k3s-stg2`
- `srv7-k3s-stg3`

Decisions already confirmed:

1. Node names as above.
2. k3s API endpoint via **VIP**.
3. Storage backend: **Longhorn only** (no Ceph).
4. Per node disks: `300GB` (nvmepool/root) + `1TB` (ssdpool/Longhorn).
5. Separate Cloudflared tunnel for staging.
6. Include full app set from testing (bootstrap/modules/scripts validation).
7. Separate secrets for staging.
8. Implement directly on `develop`.

## Documentation Is Key (Non-Negotiable)

This rollout is considered incomplete unless documentation is updated in parallel with implementation.

Rules:

1. No phase is "done" without:
   - command log evidence
   - short written outcome (what changed, what failed, what was retried)
2. Every deviation from this plan must be documented immediately.
3. Every manual fix must be converted into Git-tracked config or runbook updates.
4. Any secret-path, recipient, or bootstrap flow changes must update related docs in the same change set.

## Command Logging (Mandatory)

Use one shared command log file during execution and paste all commands there.

```bash
cd /home/lukasf/git/lukasfriedhoff
mkdir -p nix/docs/deployment/logs
export STG_LOG="nix/docs/deployment/logs/staging-3vm-$(date +%F-%H%M).md"
printf "# Staging 3-VM command log\n\n" > "$STG_LOG"
```

For every command you run:

```bash
echo "\$ <command>" | tee -a "$STG_LOG"
<command> 2>&1 | tee -a "$STG_LOG"
```

## Documentation Deliverables (Mandatory)

Create and maintain these files during execution:

- `docs/deployment/logs/staging-3vm-<timestamp>.md`
  - raw command + output log (authoritative evidence)
- `docs/deployment/staging-3vm-execution.md`
  - per-phase narrative: decisions, deviations, outcomes
- `docs/deployment/staging-3vm-postmortem.md`
  - final summary: what worked, what failed, what to automate next

Initialize execution + postmortem docs:

```bash
cd /home/lukasf/git/lukasfriedhoff/nix
cat > docs/deployment/staging-3vm-execution.md <<'EOF'
# Staging 3-VM Execution Log

## Phase Template
- Date/Time:
- Operator:
- Commands Log Reference:
- Expected Outcome:
- Actual Outcome:
- Deviations:
- Follow-up Actions:
EOF

cat > docs/deployment/staging-3vm-postmortem.md <<'EOF'
# Staging 3-VM Postmortem

## Summary
## What Worked
## What Failed
## Root Causes
## Permanent Fixes Applied
## Remaining Risks
## Follow-up TODOs
EOF
```

After each numbered phase in this plan, append:

```bash
printf "\n## Phase <N> - %s\n- Commands Log: %s\n- Outcome:\n- Deviations:\n- Next Step:\n" \
  "$(date -Iseconds)" "$STG_LOG" >> docs/deployment/staging-3vm-execution.md
```

## 1) Preflight

```bash
cd /home/lukasf/git/lukasfriedhoff/nix
git pull --rebase

cd /home/lukasf/git/lukasfriedhoff/flux-cluster
git pull --rebase

cd /home/lukasf/git/lukasfriedhoff/flux-apps
git pull --rebase
```

Host capacity on `srv4`:

```bash
ssh srv4 'hostnamectl; nproc; free -h; df -h'
ssh srv4 'virsh --connect qemu:///system list --all'
ssh srv4 'virsh --connect qemu:///system pool-list --all'
```

## 2) VM Provisioning on srv4

Target per node:

- 8 vCPU
- 16GiB RAM
- 300GB root disk on nvmepool
- 1TB longhorn disk on ssdpool

Create VMs (example; adapt flags to `new-qemu-vm.sh` current interface):

```bash
cd /home/lukasf/git/lukasfriedhoff/nix

scripts/vms/new-qemu-vm.sh \
  --name srv5-k3s-stg1 \
  --mode iso \
  --memory 16384 \
  --vcpus 8 \
  --disk-size 300 \
  --disk-pool nvmepool \
  --disk-serial srv5-k3s-stg1-root \
  --extra-disk 1024:srv5-k3s-stg1-longhorn1:ssdpool

scripts/vms/new-qemu-vm.sh \
  --name srv6-k3s-stg2 \
  --mode iso \
  --memory 16384 \
  --vcpus 8 \
  --disk-size 300 \
  --disk-pool nvmepool \
  --disk-serial srv6-k3s-stg2-root \
  --extra-disk 1024:srv6-k3s-stg2-longhorn1:ssdpool

scripts/vms/new-qemu-vm.sh \
  --name srv7-k3s-stg3 \
  --mode iso \
  --memory 16384 \
  --vcpus 8 \
  --disk-size 300 \
  --disk-pool nvmepool \
  --disk-serial srv7-k3s-stg3-root \
  --extra-disk 1024:srv7-k3s-stg3-longhorn1:ssdpool
```

## 3) Nix Repo Host Scaffolding

All commands below run in `nix/`.

```bash
cd /home/lukasf/git/lukasfriedhoff/nix
```

### 3.1 Create host dirs and management keys

```bash
scripts/homelab/new-host.sh \
  --host srv5-k3s-stg1 \
  --fqdn srv5-k3s-stg1.lab.h4xx.io \
  --root-disk-id virtio-srv5-k3s-stg1-root \
  --allow-existing

scripts/homelab/new-host.sh \
  --host srv6-k3s-stg2 \
  --fqdn srv6-k3s-stg2.lab.h4xx.io \
  --root-disk-id virtio-srv6-k3s-stg2-root \
  --allow-existing

scripts/homelab/new-host.sh \
  --host srv7-k3s-stg3 \
  --fqdn srv7-k3s-stg3.lab.h4xx.io \
  --root-disk-id virtio-srv7-k3s-stg3-root \
  --allow-existing
```

### 3.2 Ensure files exist

```bash
find hosts/homelab/srv5-k3s-stg1 hosts/homelab/srv6-k3s-stg2 hosts/homelab/srv7-k3s-stg3 -maxdepth 2 -type f | sort
```

### 3.3 Set host configuration content

Each host must contain:

- `homelab.kubernetes.enable = true`
- `homelab.kubernetes.longhorn.enable = true`
- k3s HA flags:
  - stg1: `--cluster-init`
  - stg2/stg3: `--server https://k3s-staging-api.lab.h4xx.io:6443`
  - all: `--token-file=/run/secrets/k3s-server-token` (or equivalent secret path)
- TLS SANs:
  - `k3s-staging-api.lab.h4xx.io`
  - all node FQDNs
  - VIP IP
- mount longhorn disk:
  - `/dev/disk/by-id/virtio-srvX-k3s-stgY-longhorn1` -> `/var/lib/longhorn-disk1`
- gitops bootstrap path:
  - `./overlays/staging-3vm`

## 4) Secrets (Separate Staging Secrets)

Create per-host secrets (examples):

```bash
mkdir -p secrets/profiles/personal/servers/srv5-k3s-stg1
mkdir -p secrets/profiles/personal/servers/srv6-k3s-stg2
mkdir -p secrets/profiles/personal/servers/srv7-k3s-stg3

# bootstrap password
python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits + "!@#$%^&*()-_=+"
print(''.join(secrets.choice(alphabet) for _ in range(48)))
PY
```

Then store and encrypt:

```bash
printf '<password>' > secrets/profiles/personal/servers/srv5-k3s-stg1/bootstrap-password.txt
sops --encrypt --input-type binary --in-place secrets/profiles/personal/servers/srv5-k3s-stg1/bootstrap-password.txt
```

Repeat for `srv6` and `srv7`.

Create staging k3s join token secret:

```bash
python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
```

Store encrypted token once per host scope (or a shared staging server secret path), then wire it in host config.

## 5) Inventory / Flake / Disk IDs

Update:

- `resources/homelab/disks.nix`
  - `virtio-srv5-k3s-stg1-root` purpose `root`
  - `virtio-srv5-k3s-stg1-longhorn1` purpose `longhorn`
  - same for `srv6`, `srv7`
- `resources/ssh/keys.nix`
- `resources/ssh/hosts/personal.nix`
- `flake.nix`
  - `secretsByProfile` entries for all 3 hosts
  - `nixosConfigurations` entries for all 3 hosts

Validate new host evaluations:

```bash
nix eval .#nixosConfigurations.srv5-k3s-stg1.config.networking.hostName
nix eval .#nixosConfigurations.srv6-k3s-stg2.config.networking.hostName
nix eval .#nixosConfigurations.srv7-k3s-stg3.config.networking.hostName
```

## 6) Flux Cluster Overlay (staging-3vm)

In `flux-cluster`:

```bash
cd /home/lukasf/git/lukasfriedhoff/flux-cluster
cp -a overlays/testing-srv3 overlays/staging-3vm
```

Update `overlays/staging-3vm/cluster-patch.yaml`:

- `cluster_name: staging-3vm`
- distinct external-dns TXT owner
- staging domains (`*-staging.h4xx.io`)
- staging backup endpoint overrides as needed
- longhorn backup target for staging

Keep all app stacks included (same as testing unless explicitly disabled).

Validate render:

```bash
kustomize build overlays/staging-3vm >/tmp/staging-3vm-render.yaml
```

## 7) Cloudflared Tunnel (Dedicated for Staging)

Create dedicated staging tunnel and credentials secret.

```bash
# use mgmt token from sops secret
cd /home/lukasf/git/lukasfriedhoff/nix
sops -d secrets/profiles/personal/shared/cloudflare/api-mgmt.token.txt > /tmp/cf-token.json
export CLOUDFLARE_API_TOKEN="$(jq -r '.data' /tmp/cf-token.json)"
```

Tunnel create flow (example):

```bash
cloudflared tunnel create staging-srv3vm
cloudflared tunnel route dns <TUNNEL_ID> '*.staging.h4xx.io'
```

Persist tunnel credentials into `flux-cluster` staging secrets (sops encrypted), and wire in overlay vars.

## 8) Deploy From ISO

For each node:

1. Boot NixOS ISO.
2. Copy management pubkey into installer root authorized_keys.
3. Run deploy wrapper:

```bash
cd /home/lukasf/git/lukasfriedhoff/nix

scripts/servers/deploy-from-iso.sh srv5-k3s-stg1 root@<ISO_IP_SRV5> \
  --identity ~/.ssh/personal/srv5-k3s-stg1-personal-mgmt \
  --luks-secret secrets/profiles/personal/shared/luks/srv5-k3s-stg1.txt
```

Repeat for `srv6` and `srv7`.

## 9) Unlock + Bring Up Cluster

```bash
scripts/homelab/unlock.sh srv5-k3s-stg1
scripts/homelab/unlock.sh srv6-k3s-stg2
scripts/homelab/unlock.sh srv7-k3s-stg3
```

Check k3s HA:

```bash
ssh srv5-k3s-stg1 'kubectl get nodes -o wide'
ssh srv5-k3s-stg1 'kubectl -n kube-system get pods'
```

## 10) Flux Bootstrap + Reconcile

From bootstrap node:

```bash
ssh srv5-k3s-stg1 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; flux get sources git -A'
ssh srv5-k3s-stg1 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; flux get ks -A'
ssh srv5-k3s-stg1 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; flux reconcile ks flux-system --with-source'
```

## 11) Validation Matrix

Run these and log outputs:

```bash
ssh srv5-k3s-stg1 'kubectl get nodes -o wide'
ssh srv5-k3s-stg1 'kubectl get pods -A'
ssh srv5-k3s-stg1 'kubectl get pvc -A'
ssh srv5-k3s-stg1 'kubectl get ingress -A'
ssh srv5-k3s-stg1 'kubectl -n longhorn-system get pods'
ssh srv5-k3s-stg1 'kubectl get clusters.postgresql.cnpg.io -A'
ssh srv5-k3s-stg1 'kubectl get backups.postgresql.cnpg.io -A'
ssh srv5-k3s-stg1 'flux get ks -A'
```

Endpoint checks (examples):

```bash
curl -Ik https://auth-staging.h4xx.io
curl -Ik https://dashboard-staging.h4xx.io
curl -Ik https://nextcloud-staging.h4xx.io
curl -Ik https://chat-staging.h4xx.io
```

## 12) Rollback

If staging is broken:

```bash
ssh srv4 'virsh destroy srv5-k3s-stg1 || true; virsh undefine srv5-k3s-stg1 --nvram || true'
ssh srv4 'virsh destroy srv6-k3s-stg2 || true; virsh undefine srv6-k3s-stg2 --nvram || true'
ssh srv4 'virsh destroy srv7-k3s-stg3 || true; virsh undefine srv7-k3s-stg3 --nvram || true'
```

Recreate from this runbook after fixing configuration.

## 13) Completion Checklist

- [ ] All commands executed and recorded in `docs/deployment/logs/staging-3vm-*.md`
- [ ] `docs/deployment/staging-3vm-execution.md` updated for every phase
- [ ] `docs/deployment/staging-3vm-postmortem.md` written at completion
- [ ] Secrets/docs references updated (`docs/analysis/secrets_map.md`, relevant deployment docs)
- [ ] 3 nodes Ready
- [ ] Flux ks all healthy
- [ ] Longhorn volumes healthy
- [ ] CNPG backups successful
- [ ] Cloudflared staging tunnel active
- [ ] Staging ingress/auth/media/matrix/nextcloud reachable
