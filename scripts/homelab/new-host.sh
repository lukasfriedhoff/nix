#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/homelab/new-host.sh --host <short> --fqdn <fqdn> --root-disk-id <by-id> [--ip <addr>] [--fs ext4|btrfs] [--allow-existing] [--rewrite-config] [--update-flake]

Automates personal homelab host bootstrap:
  - copies hosts/homelab/_template to hosts/homelab/<host> and fills host/domain/ip/key paths
  - writes a disko layout (defaults to ext4) using /dev/disk/by-id/<root-disk-id>
  - generates per-host management SSH key via create-management-key.sh
  - generates per-host Age key and appends it to .sops.yaml (with a hostname comment)
  - creates an encrypted LUKS passphrase under secrets/profiles/personal/shared/luks/<host>.txt
  - adds SSH config entries (access + unlock) and key installation entries

Requires: git, sops, age-keygen, python3.
EOF
}

die() { echo "error: $*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

host=""
fqdn=""
ip_hint=""
root_disk_id=""
fs_type="ext4"
allow_existing=false
rewrite_config=false
update_flake=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) host="$2"; shift 2;;
    --fqdn) fqdn="$2"; shift 2;;
    --ip) ip_hint="$2"; shift 2;;
    --root-disk-id) root_disk_id="$2"; shift 2;;
    --fs) fs_type="$2"; shift 2;;
    --allow-existing) allow_existing=true; shift 1;;
    --rewrite-config) rewrite_config=true; shift 1;;
    --update-flake) update_flake=true; shift 1;;
    -h|--help) usage; exit 0;;
    *) die "unknown argument: $1";;
  esac
done

[[ -n "$host" ]] || die "--host is required"
[[ -n "$fqdn" ]] || die "--fqdn is required"
[[ -n "$root_disk_id" ]] || die "--root-disk-id is required (e.g. nvme-SAMSUNG...)"
case "$fs_type" in
  ext4|btrfs) ;;
  *) die "--fs must be ext4 or btrfs";;
esac

need_cmd git
need_cmd sops
need_cmd age-keygen
need_cmd python3

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

template_dir="hosts/homelab/_template"
dest_dir="hosts/homelab/${host}"
[[ -d "$template_dir" ]] || die "template not found at ${template_dir}"
if [[ -e "$dest_dir" ]]; then
  if [[ "$allow_existing" == true ]]; then
    echo ">> Reusing existing ${dest_dir}"
  else
    die "destination already exists: ${dest_dir} (pass --allow-existing to reuse)"
  fi
else
  echo ">> Copying template to ${dest_dir}"
  cp -r "$template_dir" "$dest_dir"
fi

domain="${fqdn#*.}"
[[ "$domain" == "$fqdn" ]] && domain=""

mgmt_pub_secret="secrets/profiles/personal/servers/${host}/ssh/${host}-personal-mgmt.pub"
if [[ -f "$mgmt_pub_secret" ]]; then
  echo ">> Reusing existing management key ${mgmt_pub_secret}"
else
  echo ">> Generating per-host management key"
  "${repo_root}/scripts/servers/create-management-key.sh" "$host" personal
fi
[[ -f "$mgmt_pub_secret" ]] || die "expected management pubkey at ${mgmt_pub_secret}"
mgmt_pub="$(sops -d "$mgmt_pub_secret")"

echo ">> Writing disko layout to ${dest_dir}/disko.nix (fs=${fs_type})"
mkdir -p "$dest_dir"
if [[ -f "${dest_dir}/disko.nix" ]] && [[ "$rewrite_config" == false ]]; then
  echo "   keeping existing disko.nix (use --rewrite-config to regenerate)"
else
  if [[ "$fs_type" == "ext4" ]]; then
    cat > "${dest_dir}/disko.nix" <<EOF
{ ... }:
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/${root_disk_id}";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            priority = 1;
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              extraArgs = [ "-n" "EFI" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    };
  };
}
EOF
  else
    cat > "${dest_dir}/disko.nix" <<EOF
{ ... }:
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/${root_disk_id}";
      content = {
        type = "gpt";
        partitions = {
          boot = {
            priority = 1;
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              extraArgs = [ "-n" "EFI" ];
            };
          };
          root = {
            size = "100%";
            content = {
              type = "luks";
              name = "cryptroot";
              settings.allowDiscards = true;
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/@" = { mountpoint = "/"; };
                  "/@nix" = { mountpoint = "/nix"; };
                };
              };
            };
          };
        };
      };
    };
  };
}
EOF
  fi
fi

age_key="secrets/profiles/personal/servers/${host}/age.key"
if [[ -f "$age_key" ]]; then
  echo ">> Reusing existing Age key ${age_key}"
else
  echo ">> Generating Age key at ${age_key}"
  mkdir -p "$(dirname "$age_key")"
  age-keygen -o "$age_key"
fi
echo ">> Encrypting Age key with sops"
SOPS_CONFIG="${repo_root}/.sops.yaml" sops --encrypt --input-type binary --in-place "$age_key"
age_recipient="$(age-keygen -y "$age_key")"

echo ">> Ensuring .sops.yaml contains Age recipient (commented with hostname)"
python3 - "$host" "$age_recipient" ".sops.yaml" <<'PY'
import re, sys, pathlib
host, recipient, path = sys.argv[1], sys.argv[2], pathlib.Path(sys.argv[3])
text = path.read_text()
m = re.search(
    r"(  - path_regex: \^secrets/profiles/personal/servers/.*?\n    key_groups:\n      - age:\n)((?:          - .*\n)+)",
    text,
    re.S,
)
if not m:
    sys.exit("could not locate personal servers block in .sops.yaml")
entries = m.group(2)
if recipient in entries:
    sys.exit(0)
new_entries = entries + f"          - {recipient} # {host}\n"
updated = text[: m.start(2)] + new_entries + text[m.end(2) :]
path.write_text(updated)
PY

luks_secret="secrets/profiles/personal/shared/luks/${host}.txt"
if [[ -f "$luks_secret" ]]; then
  echo ">> LUKS passphrase already exists at ${luks_secret}"
else
  echo ">> Creating LUKS passphrase at ${luks_secret}"
  mkdir -p "$(dirname "$luks_secret")"
  pass="$(python3 - <<'PY'
import secrets, string
alphabet = string.ascii_letters + string.digits + "!@#$%^&*()-_=+"
print(''.join(secrets.choice(alphabet) for _ in range(48)))
PY
)"
  printf "%s\n" "$pass" > "$luks_secret"
  sops --encrypt --input-type binary --in-place "$luks_secret"
fi

config_path="${dest_dir}/configuration.nix"
if [[ -f "$config_path" ]] && [[ "$rewrite_config" == false ]]; then
  echo ">> Keeping existing ${config_path} (use --rewrite-config to regenerate)"
else
  echo ">> Writing ${config_path}"
  python3 - "$host" "$fqdn" "$domain" "$ip_hint" "$mgmt_pub" "$config_path" <<'PY'
import sys, pathlib
host, fqdn, domain, ip_hint, pubkey, path = sys.argv[1:]
ip_comment = f"# {host} {fqdn}" + (f" {ip_hint}" if ip_hint else "")
domain_eff = domain or fqdn
p = pathlib.Path(path)
cfg = f"""{{
  inputs,
  secrets,
  ...
}}:

{{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
  ];

  networking.hostName = "{host}";
  networking.domain = "{domain_eff}";

  homelab.personalServer = {{
    enable = true;
    managementPubKey = "ssh/{host}-personal-mgmt.pub";
    usePasswordAuth = false;
  }};

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  sops.age.keyFile = "/home/lukasf/.config/sops/age/keys.txt";

  boot.initrd.network = {{
    enable = true;
    ssh = {{
      enable = true;
      port = 2222;
      authorizedKeys = [ "{pubkey.strip()}" ];
      generateHostKeys = true;
    }};
  }};

  networking.extraHosts = ''
    {ip_comment}
  '';
}}
"""
p.write_text(cfg)
PY
fi

echo ">> Adding key install entry to resources/ssh/keys.nix"
python3 - "$host" "resources/ssh/keys.nix" <<'PY'
import sys, pathlib
host, path = sys.argv[1], pathlib.Path(sys.argv[2])
block = f'''  {{
    secret = "ssh/{host}-personal-mgmt.priv";
    path = ".ssh/personal/{host}-personal-mgmt";
  }}
'''
txt = path.read_text()
if f'/{host}-personal-mgmt.priv' in txt:
    sys.exit(0)
if not txt.strip().endswith(']'):
    sys.exit("unexpected format in resources/ssh/keys.nix")
updated = txt.rstrip().rstrip(']') + "\n" + block + "]\n"
path.write_text(updated)
PY

echo ">> Adding SSH host entries (access + unlock) to resources/ssh/hosts.nix"
python3 - "$host" "$fqdn" "$ip_hint" "resources/ssh/hosts.nix" <<'PY'
import sys, pathlib
host, fqdn, ip_hint, path = sys.argv[1], sys.argv[2], sys.argv[3], pathlib.Path(sys.argv[4])
host_target = ip_hint or fqdn or host
entry_access = f'''    {{
      match = "{host}";
      alias = "{host}";
      hostName = "{host_target}";
      user = "root";
      keyName = "{host}-personal-mgmt";
    }}
'''
entry_unlock = f'''    {{
      match = "unlock-{host}";
      alias = "unlock-{host}";
      hostName = "{host_target}";
      port = 2222;
      user = "root";
      keyName = "{host}-personal-mgmt";
    }}
'''
txt = path.read_text()
if f'match = "{host}"' in txt and f'match = "unlock-{host}"' in txt:
    sys.exit(0)
anchor = txt.rfind("  ];")
if anchor == -1:
    sys.exit("unexpected format in resources/ssh/hosts.nix (missing closing '  ];')")
updated = txt[:anchor].rstrip() + "\n" + entry_access + entry_unlock + txt[anchor:]
path.write_text(updated)
PY

flake_path="flake.nix"
if [[ "$update_flake" == true ]]; then
  echo ">> Updating flake.nix with secretsByProfile and nixosConfigurations entry"
  python3 - "$host" "$flake_path" <<'PY'
import sys, pathlib, re
host, path = sys.argv[1], pathlib.Path(sys.argv[2])
text = path.read_text()

entry = f'''            {host} = {{
              primary = personalServerRoot "{host}";
              shared = sharedCommonRoot;
              profileShared = personalSharedRoot;
              profileCommon = personalCommonDesktopRoot;
              root = personalServerRoot "{host}";
              personal = personalServerRoot "{host}";
            }};
'''

# Insert secretsByProfile entry if missing
profile_start = text.find("secretsByProfile = {")
if profile_start == -1:
  sys.exit("could not find secretsByProfile block in flake.nix")
profile_end = text.find("\n          };", profile_start)
if profile_end == -1:
  sys.exit("could not find end of secretsByProfile block in flake.nix")
profile_body = text[profile_start:profile_end]
if f"{host} =" not in profile_body:
  text = text[:profile_end] + "\n" + entry + text[profile_end:]

# Insert nixosConfigurations entry if missing
nixos_marker = "nixosConfigurations = {"
nidx = text.find(nixos_marker)
if nidx == -1:
  sys.exit("could not find nixosConfigurations block in flake.nix")

nixos_entry = f'''
            {host} = mkNixosHost "{host}" (
              personalHomelabServerModules ++ [
                ./hosts/homelab/{host}/configuration.nix
              ]
            );
'''
nixos_end = text.find("\n          };", nidx)
if nixos_end == -1:
  sys.exit("could not find end of nixosConfigurations block in flake.nix")
nixos_body = text[nidx:nixos_end]
if f"{host} =" not in nixos_body:
  text = text[:nixos_end] + nixos_entry + text[nixos_end:]

path.write_text(text)
PY
else
  echo ">> Next: add flake entries and deploy."
fi

echo ">> Done."
