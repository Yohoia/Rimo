#!/bin/bash
set -euo pipefail
project_dir=$(cd -- "$(dirname -- "$0")/.." && pwd)
output_dir=${1:-"$project_dir/.build/audio-driver"}
driver_dir="$output_dir/SofoMicrophone.driver"
/bin/mkdir -p "$driver_dir/Contents/MacOS"
/usr/bin/xcrun clang -std=c11 -O2 -Wall -Wextra -Wno-unused-parameter -Werror \
    -arch arm64 -arch x86_64 -mmacosx-version-min=13.0 -bundle \
    -framework CoreAudio -framework CoreFoundation \
    "$project_dir/sofo/AudioDriver/SofoMicrophone.c" \
    -o "$driver_dir/Contents/MacOS/SofoMicrophone"
/bin/cp "$project_dir/sofo/AudioDriver/Info.plist" "$driver_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - --timestamp=none "$driver_dir"
/usr/bin/codesign --verify --strict "$driver_dir"
