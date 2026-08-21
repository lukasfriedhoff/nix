[
  {
    match = "misp-dev";
    alias = "misp-dev";
    user = "misp";
    keyName = "ci";
  }
  {
    match = "aruba3oobm";
    alias = "aruba3oobm";
    user = "admin";
    keyName = "aruba3";
    extraOptions = {
      PubkeyAcceptedAlgorithms = "+ssh-rsa";
    };
  }
  {
    match = "aruba3";
    alias = "aruba3";
    user = "admin";
    keyName = "aruba3";
    extraOptions = {
      PubkeyAcceptedAlgorithms = "+ssh-rsa";
    };
  }
  {
    match = "jh";
    alias = "jh";
    user = "lukasfriedhoff";
    keyName = "ci";
  }
  {
    match = "jh3";
    alias = "jh3";
    user = "lukasfriedhoff";
    keyName = "ci";
  }
  {
    match = "jh4";
    alias = "jh4";
    user = "lukasfriedhoff";
    keyName = "ci";
  }
  {
    match = "lf-alma-02";
    alias = "lf-alma-02";
    user = "nuagealerting";
    keyName = "ci";
  }
  {
    match = "clientportdown01";
    alias = "cpd01";
    user = "clientportdown";
    keyName = "clientportdown01";
  }
  {
    match = "netbox04";
    alias = "netbox04";
    user = "netbox";
    keyName = "netbox04";
  }
  {
    match = "dacosoworksca01";
    alias = "dacosoworksca01";
    hostName = "10.0.33.26";
    user = "ca";
    keyName = "dacosoworksca01";
    extraOptions = {
      # Prefer post-quantum hybrid key exchange (^ prepends to the default
      # list, so older servers still negotiate a classical KEX). Auth stays
      # ed25519: OpenSSH has no PQ user-authentication keys yet.
      KexAlgorithms = "^mlkem768x25519-sha256,sntrup761x25519-sha512@openssh.com";
    };
  }
]
