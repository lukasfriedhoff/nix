[
  # Work desktop keys (installed on macbook-pro via work profile secrets).
  {
    secret = "ssh/github.priv";
    path = ".ssh/work/github";
    scope = "work";
  }
  {
    secret = "ssh/bitbucket.priv";
    path = ".ssh/work/bitbucket";
    scope = "work";
  }
  {
    secret = "ssh/ci.priv";
    path = ".ssh/work/ci";
    scope = "work";
  }
  {
    secret = "ssh/aruba3.priv";
    path = ".ssh/work/aruba3";
    scope = "work";
  }

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
]
