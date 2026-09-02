[
  # Work keys land in ~/.ssh/work via work profile secrets; add group24
  # entries here as access is provisioned (scope = "work").

  # Add new personal homelab management keys here, e.g.:
  # { secret = "ssh/<short>-personal-mgmt.priv"; path = ".ssh/personal/<short>-personal-mgmt"; }
  {
    secret = "ssh/chaospott_noc.priv";
    path = ".ssh/personal/chaospott/noc";
    scope = "personal";
  }
  {
    secret = "ssh/chaospott_git.priv";
    path = ".ssh/personal/chaospott/git";
    scope = "personal";
  }
  {
    secret = "ssh/chaospott_door.priv";
    path = ".ssh/personal/chaospott/door";
    scope = "personal";
  }
  {
    secret = "ssh/ci.priv";
    path = ".ssh/personal/ci";
    scope = "personal";
  }
  {
    secret = "ssh/docker-host.priv";
    path = ".ssh/personal/docker-host";
    scope = "personal";
  }
  {
    secret = "ssh/h4xxsrv1.priv";
    path = ".ssh/personal/h4xxsrv1";
    scope = "personal";
  }
  {
    secret = "git-personal-ed25519.priv";
    path = ".ssh/personal/id_ed25519";
    scope = "personal";
  }
  {
    secret = "ssh/ionos1.priv";
    path = ".ssh/personal/ionos1";
    scope = "personal";
  }
  {
    secret = "ssh/ionos2.priv";
    path = ".ssh/personal/ionos2";
    scope = "personal";
  }
  {
    secret = "ssh/nas01.priv";
    path = ".ssh/personal/nas01";
    scope = "personal";
  }
  {
    secret = "ssh/nas01-unlock.priv";
    path = ".ssh/personal/nas01-unlock";
    scope = "personal";
  }
  {
    secret = "ssh/storage01.priv";
    path = ".ssh/personal/storage01";
    scope = "personal";
  }
  {
    secret = "ssh/srv4.priv";
    path = ".ssh/personal/srv4";
    scope = "personal";
  }

  {
    secret = "ssh/srv1-personal-mgmt.priv";
    path = ".ssh/personal/srv1-personal-mgmt";
    scope = "personal";
  }

  {
    secret = "ssh/srv2-personal-mgmt.priv";
    path = ".ssh/personal/srv2-personal-mgmt";
    scope = "personal";
  }
  {
    secret = "ssh/mikrotikrb5009.priv";
    path = ".ssh/personal/mikrotikrb5009";
    scope = "personal";
  }
  {
    secret = "ssh/travelrouter.priv";
    path = ".ssh/personal/travelrouter";
    scope = "personal";
  }

  {
    secret = "ssh/srv3-personal-mgmt.priv";
    path = ".ssh/personal/srv3-personal-mgmt";
    scope = "personal";
  }
  {
    secret = "ssh/srv5-k3s-stg1-personal-mgmt.priv";
    path = ".ssh/personal/srv5-k3s-stg1-personal-mgmt";
    scope = "personal";
  }
  {
    secret = "ssh/srv6-k3s-stg2-personal-mgmt.priv";
    path = ".ssh/personal/srv6-k3s-stg2-personal-mgmt";
    scope = "personal";
  }
  {
    secret = "ssh/srv7-k3s-stg3-personal-mgmt.priv";
    path = ".ssh/personal/srv7-k3s-stg3-personal-mgmt";
    scope = "personal";
  }
  {
    secret = "ssh/srv8-personal-mgmt.priv";
    path = ".ssh/personal/srv8-personal-mgmt";
    scope = "personal";
  }
  {
    secret = "ssh/srv9-personal-mgmt.priv";
    path = ".ssh/personal/srv9-personal-mgmt";
    scope = "personal";
  }
]
