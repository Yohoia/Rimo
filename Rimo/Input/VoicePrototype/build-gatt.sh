#!/bin/bash
set -euo pipefail

source_dir=$(cd -- "$(dirname -- "$0")" && pwd)
build_dir=${RIMO_GATT_BUILD_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/Rimo-voice-gatt.XXXXXXXX")}
app="$build_dir/Rimo Voice Probe.app"
mkdir -p "$app/Contents/MacOS"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>VoiceProbe</string>
    <key>CFBundleIdentifier</key><string>cn.yohoia.rimo.voice-probe</string>
    <key>CFBundleName</key><string>Rimo Voice Probe</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>检查已配对的 A2540 遥控器是否向 Rimo 公开蓝牙语音服务。</string>
</dict>
</plist>
PLIST
if [[ -n ${1:-} ]]; then
    plutil -insert RimoRemoteName -string "$1" "$app/Contents/Info.plist"
fi
xcrun swiftc -parse-as-library "$source_dir/GATTDiscovery.swift" -o "$app/Contents/MacOS/VoiceProbe"
codesign --force --sign - "$app"
printf '%s\n' "$app"
