{
  lib,
  stdenv,
  buildGoModule,
  fetchFromGitHub,
  installShellFiles,
}:

buildGoModule (finalAttrs: {
  pname = "velero";
  version = "1.9.4";
  binaryName = "velero-${finalAttrs.version}";

  src = fetchFromGitHub {
    owner = "vmware-tanzu";
    repo = "velero";
    tag = "v${finalAttrs.version}";
    hash = "sha256-1fr0o98O7rtKoL1rqx8GasofmJYgp8sr+oNRbUpwVR8=";
  };

  ldflags = [
    "-s"
    "-w"
    "-X github.com/vmware-tanzu/velero/pkg/buildinfo.Version=v${finalAttrs.version}"
    "-X github.com/vmware-tanzu/velero/pkg/buildinfo.ImageRegistry=velero"
    "-X github.com/vmware-tanzu/velero/pkg/buildinfo.GitTreeState=clean"
    "-X github.com/vmware-tanzu/velero/pkg/buildinfo.GitSHA=none"
  ];

  vendorHash = "sha256-7YlQpWfWSgqQUOXRHuZ5YBmZ/w4VZ21RcaccCokhBkk=";

  excludedPackages = [
    "issue-template-gen"
    "release-tools"
    "v1"
    "velero-restic-restore-helper"
  ];

  doCheck = false;
  doInstallCheck = true;

  nativeBuildInputs = [ installShellFiles ];

  postInstall = ''
    ${lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      $out/bin/velero completion bash > ${finalAttrs.binaryName}.bash
      $out/bin/velero completion zsh > ${finalAttrs.binaryName}.zsh
      installShellCompletion \
        --cmd ${finalAttrs.binaryName} \
        --bash ${finalAttrs.binaryName}.bash \
        --zsh ${finalAttrs.binaryName}.zsh
    ''}

    mv $out/bin/velero $out/bin/${finalAttrs.binaryName}
  '';

  installCheckPhase = ''
    $out/bin/${finalAttrs.binaryName} version --client-only | grep ${finalAttrs.version} > /dev/null
  '';

  meta = {
    description = "Utility for managing disaster recovery, specifically for your Kubernetes cluster resources and persistent volumes";
    homepage = "https://velero.io/";
    changelog = "https://github.com/vmware-tanzu/velero/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ mbode ];
    mainProgram = finalAttrs.binaryName;
  };
})
