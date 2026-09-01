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

  # Work defaults
  work = {
    user = "lukasfriedhoff";
    defaultIdentity = "~/.ssh/work/id_ed25519";
    keyDir = "~/.ssh/work";
  };
}
