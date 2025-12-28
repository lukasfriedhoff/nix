[
  # Per-profile SOPS secret that contains private HostName mappings.
  #
  # Create (encrypted) as:
  #   secrets/profiles/<personal|work>/.../ssh/hostnames-private.conf
  #
  # The decrypted file is installed to ~/.ssh/config.d/15-hostnames-private so it
  # overrides the generated ~/.ssh/config.d/20-hosts HostName values.
  {
    secret = "ssh/hostnames-private.conf";
    path = ".ssh/config.d/15-hostnames-private";
    mode = "600";
  }
]
