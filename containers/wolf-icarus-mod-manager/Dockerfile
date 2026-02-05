ARG BASE_APP_IMAGE=ghcr.io/games-on-whales/base-app:edge
FROM ${BASE_APP_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive
ARG ICARUS_MOD_MANAGER_VERSION=2.3.6
ARG ICARUS_MOD_MANAGER_VERSION_UNDERSCORED=2_3_6
ARG ICARUS_MOD_MANAGER_URL=https://github.com/Jimk72/Icarus_Software/raw/main/Icarus_Mod_Manager_${ICARUS_MOD_MANAGER_VERSION_UNDERSCORED}.zip

ARG REQUIRED_PACKAGES=" \
    cabextract \
    curl \
    libasound2-plugins:i386 \
    libdbus-1-3:i386 \
    libfreetype6:i386 \
    libnotify4 \
    libsecret-1-0 \
    libsdl2-2.0-0:i386 \
    libsqlite3-0:i386 \
    libvulkan1 \
    libvulkan1:i386 \
    mesa-vulkan-drivers \
    mesa-vulkan-drivers:i386 \
    p7zip-full \
    wine-stable \
    wine32 \
    wine64 \
    winetricks \
    xdg-utils \
    xz-utils \
    zenity \
    "

RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y --no-install-recommends $REQUIRED_PACKAGES && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/icarus-mod-manager && \
    curl -L -o /tmp/icarus-mod-manager.zip "$ICARUS_MOD_MANAGER_URL" && \
    unzip -q /tmp/icarus-mod-manager.zip -d /opt/icarus-mod-manager && \
    rm /tmp/icarus-mod-manager.zip

COPY --chmod=777 startup.sh /opt/gow/startup-app.sh

ENV XDG_RUNTIME_DIR=/tmp/.X11-unix

ARG IMAGE_SOURCE
LABEL org.opencontainers.image.source=$IMAGE_SOURCE
