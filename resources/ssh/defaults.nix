{
  common = {
    port = 22;
    controlPersist = "10m";
  };

  personal = {
    user = "lukasf";
    defaultIdentity = "~/.ssh/personal/id_ed25519";
    keyDir = "~/.ssh/personal";
  };

  # Work / Dacoso defaults
  dacoso = {
    user = "lukasfriedhoff";
    defaultIdentity = "~/.ssh/work/ci";
    keyDir = "~/.ssh/work";
  };
}
