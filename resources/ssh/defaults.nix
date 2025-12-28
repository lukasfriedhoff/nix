{
  common = {
    port = 22;
    controlPersist = "10m";
  };

  personal = {
    user = "lukasf";
    defaultIdentity = "~/.ssh/personal/id_ed25519";
  };

  # Work / Dacoso defaults
  dacoso = {
    user = "lukasfriedhoff";
    defaultIdentity = "~/.ssh/id_ed25519_dacoso";
  };
}
