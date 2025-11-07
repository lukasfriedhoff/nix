{ config, pkgs, lib, ... }:

let
  fluxPlugins = ''
plugins:
  flux-kustomization-reconcile:
    shortCut: Shift-R
    description: Flux reconcile kustomization
    scopes:
      - kustomizations.kustomize.toolkit.fluxcd.io
    command: flux
    args:
      - reconcile
      - kustomization
      - $NAME
      - --namespace
      - $NAMESPACE
  flux-kustomization-suspend:
    shortCut: Shift-S
    description: Flux suspend kustomization
    scopes:
      - kustomizations.kustomize.toolkit.fluxcd.io
    command: flux
    args:
      - suspend
      - kustomization
      - $NAME
      - --namespace
      - $NAMESPACE
  flux-kustomization-resume:
    shortCut: Shift-U
    description: Flux resume kustomization
    scopes:
      - kustomizations.kustomize.toolkit.fluxcd.io
    command: flux
    args:
      - resume
      - kustomization
      - $NAME
      - --namespace
      - $NAMESPACE
  flux-helmrelease-reconcile:
    shortCut: Shift-H
    description: Flux reconcile HelmRelease
    scopes:
      - helmreleases.helm.toolkit.fluxcd.io
    command: flux
    args:
      - reconcile
      - helmrelease
      - $NAME
      - --namespace
      - $NAMESPACE
  flux-helmrelease-suspend:
    shortCut: Shift-J
    description: Flux suspend HelmRelease
    scopes:
      - helmreleases.helm.toolkit.fluxcd.io
    command: flux
    args:
      - suspend
      - helmrelease
      - $NAME
      - --namespace
      - $NAMESPACE
  flux-helmrelease-resume:
    shortCut: Shift-K
    description: Flux resume HelmRelease
    scopes:
      - helmreleases.helm.toolkit.fluxcd.io
    command: flux
    args:
      - resume
      - helmrelease
      - $NAME
      - --namespace
      - $NAMESPACE
'';

  fluxHotkeys = ''
hotKeys:
  fluxKustomizations:
    shortCut: Shift-F
    description: View Flux Kustomizations
    command: :resource kustomizations.kustomize.toolkit.fluxcd.io
  fluxHelmReleases:
    shortCut: Shift-L
    description: View Flux HelmReleases
    command: :resource helmreleases.helm.toolkit.fluxcd.io
'';
in
{
  programs.k9s = {
    enable = true;
    package = pkgs.k9s;
  };

  home.packages = lib.mkIf (pkgs ? fluxcd) [ pkgs.fluxcd ];

  home.file.".config/k9s/plugins.yml" = {
    text = fluxPlugins;
  };

  home.file.".config/k9s/hotkeys.yml" = {
    text = fluxHotkeys;
  };
}
