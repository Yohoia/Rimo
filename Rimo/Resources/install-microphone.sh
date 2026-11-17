#!/bin/bash
# Installs only Rimo's input driver. CoreAudio loads it on its next restart.
set -euo pipefail
[[ $EUID -eq 0 && $# -eq 1 ]] || exit 64
source_driver=$1
target_dir=/Library/Audio/Plug-Ins/HAL
target="$target_dir/RimoMicrophone.driver"
/usr/bin/codesign --verify --strict "$source_driver"
[[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_driver/Contents/Info.plist") == cn.yohoia.rimo.audio ]] || exit 65
if [[ -e "$target" ]]; then
    echo 'Rimo 麦克风驱动已存在；请先检查现有版本。' >&2
    exit 66
fi
/bin/mkdir -p "$target_dir"
staging=$(/usr/bin/mktemp -d "$target_dir/.Rimo-install.XXXXXXXX")
trap '/bin/rm -rf "$staging"' EXIT
/usr/bin/ditto --norsrc --noextattr --qtn "$source_driver" "$staging/RimoMicrophone.driver"
/usr/sbin/chown -R root:wheel "$staging/RimoMicrophone.driver"
/bin/chmod -R go-w "$staging/RimoMicrophone.driver"
/usr/bin/codesign --verify --strict "$staging/RimoMicrophone.driver"
/bin/mv "$staging/RimoMicrophone.driver" "$target"
# Preserve active calls/recordings: do not restart coreaudiod automatically.
