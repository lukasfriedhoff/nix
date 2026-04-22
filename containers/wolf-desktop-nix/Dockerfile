ARG BASE_APP_IMAGE=ghcr.io/games-on-whales/xfce:edge
FROM ${BASE_APP_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG REQUIRED_PACKAGES="ca-certificates curl git jq nix-bin"

RUN apt-get update \
    && apt-get install -y --no-install-recommends ${REQUIRED_PACKAGES} \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -m 0755 /etc/nix \
    && printf '%s\n' \
      'experimental-features = nix-command flakes' \
      > /etc/nix/nix.conf \
    && printf '%s\n' \
      '# Keep nix command features available in interactive shells.' \
      'export NIX_CONFIG="experimental-features = nix-command flakes"' \
      > /etc/profile.d/10-nix-features.sh

ARG IMAGE_SOURCE
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
