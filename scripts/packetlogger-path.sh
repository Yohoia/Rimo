#!/bin/bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
if [[ -n ${RIMO_PACKETLOGGER_APP:-} ]]; then
    if [[ ! -x "$RIMO_PACKETLOGGER_APP/Contents/Resources/packetlogger" ]]; then
        echo 'error: RIMO_PACKETLOGGER_APP must point to a PacketLogger.app that contains the command-line tool.' >&2
        exit 2
    fi
    printf '%s\n' "$RIMO_PACKETLOGGER_APP"
    exit 0
fi

for app in "$project_dir/.local/PacketLogger.app" /Applications/PacketLogger.app; do
    if [[ -x "$app/Contents/Resources/packetlogger" ]]; then
        printf '%s\n' "$app"
        exit 0
    fi
done
exit 1
