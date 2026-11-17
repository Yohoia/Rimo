#!/bin/bash
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
project_dir=$(cd -- "$source_dir/../../.." && pwd)
output_dir="$project_dir/.build/voice-prototype"
mkdir -p "$output_dir"
xcrun swiftc -parse-as-library "$source_dir/Capture.swift" -o "$output_dir/capture"

case "${1:-}" in
    --check) exec "$output_dir/capture" --check ;;
    ''|--enable-feature) ;;
    *) echo 'Usage: bash run.sh [--check|--enable-feature]' >&2; exit 64 ;;
esac

export RIMO_OPUS_LIBRARY=${RIMO_OPUS_LIBRARY:-/opt/homebrew/lib/libopus.dylib}
if [[ ! -r "$RIMO_OPUS_LIBRARY" && -r /usr/local/lib/libopus.dylib ]]; then
    export RIMO_OPUS_LIBRARY=/usr/local/lib/libopus.dylib
fi
if [[ ! -r "$RIMO_OPUS_LIBRARY" ]]; then
    echo '找不到本机 libopus。可用 RIMO_OPUS_LIBRARY 指定库文件。' >&2
    exit 2
fi

raw=$(mktemp "$output_dir/.frames.XXXXXXXX")
trap 'unlink "$raw"' EXIT
"$output_dir/capture" "$raw" "$@"
session_dir=$(mktemp -d "$output_dir/session.XXXXXXXX")
python3 "$source_dir/decode.py" hid "$raw" "$session_dir/A2540.wav"
