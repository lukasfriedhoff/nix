#!/bin/bash

set -euo pipefail

source /opt/gow/bash-lib/utils.sh

app_dir="${HOME}/icarus-mod-manager"
wine_prefix="${HOME}/.wine-icarus-mod-manager"

mkdir -p "${app_dir}" "${wine_prefix}"

if [ ! -e "${app_dir}/IcarusModManager.exe" ]; then
    gow_log "Priming Icarus Mod Manager files in ${app_dir}"
    cp -R --no-preserve=mode,ownership /opt/icarus-mod-manager/. "${app_dir}/"
fi

export WINEPREFIX="${wine_prefix}"
export WINEARCH=win64
export WINEDEBUG=-all

if [ ! -f "${wine_prefix}/.dotnetdesktop8-installed" ]; then
    gow_log "Installing .NET Desktop Runtime 8 via winetricks (first run only)"
    winetricks -q dotnetdesktop8
    touch "${wine_prefix}/.dotnetdesktop8-installed"
fi

exec wine "${app_dir}/IcarusModManager.exe"
