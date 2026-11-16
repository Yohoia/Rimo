#!/bin/bash
# A foreground, session-scoped capture. No daemon or persistent privilege is installed.
set -euo pipefail
umask 077
cli=$1
session=$2
parent=$3
[[ $EUID -eq 0 && -d "$session" && $parent =~ ^[0-9]+$ ]] || exit 64
/usr/bin/codesign --verify --strict -R='anchor apple' "$cli"
[[ ! -e "$session/stop" ]] || exit 0
child=''
cleanup() {
    if [[ -n "$child" ]]; then
        kill -TERM "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 0' TERM INT HUP
"$cli" convert --output "$session/trace.pklg" 2>"$session/error.txt" &
child=$!
started=$SECONDS
while kill -0 "$child" 2>/dev/null; do
    [[ ! -e "$session/stop" ]] || exit 0
    kill -0 "$parent" 2>/dev/null || exit 0
    if (( SECONDS - started >= 28800 )); then
        echo '收音已启用 8 小时，请停止后重新启用。' >> "$session/error.txt"
        exit 1
    fi
    [[ -d "$session" ]] || exit 0
    size=$(/usr/bin/stat -f '%z' "$session/trace.pklg")
    if (( size > 33554432 )); then
        echo '本次蓝牙采集已达到容量上限，请停止后重新启用。' >> "$session/error.txt"
        exit 1
    fi
    /bin/sleep 0.1
done
wait "$child"
child=''
