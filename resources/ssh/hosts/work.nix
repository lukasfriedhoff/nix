# Group24 work hosts. Add entries as access is provisioned; see
# resources/ssh/hosts/personal.nix for the entry format.
[
  # Mac -> tux reverse SSH tunnel (llama.cpp). No `hostName` on purpose: the
  # private IP is network-dependent and provisioned via hostnames-private.conf
  # (config.d/15-* overrides this 20-* default), so it is never hardcoded here.
  # Identity: tunnel-tux -> ~/.ssh/work/tunnel-tux (work profile, keys.nix).
  {
    match = "tux";
    alias = "tux";
    user = "lukasf";
    keyName = "tunnel-tux";
  }
  {
    match = "academy-gitlab";
    alias = "acgl";
    hostName = "172.16.18.200";
    user = "gitlab";
    keyName = "academy-gitlab";
    port = 2222;
  }
  # Academy GitLab git remote (gitlab-shell on :22, same node). Pubkey is
  # registered on the lukas.friedhoff GitLab account.
  {
    match = "gitlab.apps.new-academy.group24.de";
    alias = "gitlab.apps.new-academy.group24.de";
    user = "git";
    keyName = "academy-gitlab-git";
    port = 22;
  }
]
