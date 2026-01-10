# home/programs/aws/default.nix
{
  config,
  pkgs,
  lib,
  ...
}:

let
  aws = pkgs.awscli2;
in
{
  # Replace s3cli with the official AWS CLI
  home.packages = [
    aws
    pkgs.stu
    pkgs.minio-client
  ];

  # # Bash completion for `aws`
  # programs.bash = {
  #   enable = true;
  #   enableCompletion = true;
  #   # `aws_completer` is shipped inside awscli2
  #   initExtra = ''
  #     if command -v aws &>/dev/null; then
  #       # Bash completion (officially supported)
  #       complete -C ${aws}/bin/aws_completer aws
  #     fi
  #   '';
  # };

  # # Zsh completion for `aws` (use bashcompinit bridge)
  # programs.zsh = {
  #   enable = true;
  #   enableCompletion = true;
  #   initExtra = ''
  #     if command -v aws &>/dev/null; then
  #       autoload -U +X bashcompinit && bashcompinit
  #       complete -C ${aws}/bin/aws_completer aws
  #     fi
  #   '';
  # };

  # # Create ~/.aws/config (safe—no secrets here). Put profiles you need.
  # xdg.configFile."aws/config".text = lib.mkDefault ''
  #   [default]
  #   region = eu-central-1
  #   output = json

  #   # --- Example: AWS SSO profile ---
  #   [profile my-sso]
  #   sso_start_url = https://my-sso-portal.awsapps.com/start
  #   sso_region    = eu-central-1
  #   sso_account_id = 123456789012
  #   sso_role_name  = Admin
  #   region = eu-central-1
  #   output = json
  # '';

  # If you want classic access keys WITHOUT committing secrets:
  # Keep this commented here; create it via SOPS/HM instead.
  # xdg.configFile."aws/credentials".text = ''
  #   [default]
  #   aws_access_key_id = AKIA...
  #   aws_secret_access_key = ...
  # '';

  # Optional: store session/cache under XDG (tidy home)
  # AWS CLI v2 already respects ~/.aws, which we place under XDG config via HM.
}
