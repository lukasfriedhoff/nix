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
]
