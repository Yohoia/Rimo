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
    [[ $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target/Contents/Info.plist") == cn.yohoia.rimo.audio ]] || exit 66
fi
/bin/mkdir -p "$target_dir"
lock="$target_dir/.Rimo-install.lock"
if ! /bin/mkdir "$lock" 2>/dev/null; then
    echo '已有麦克风安装正在运行，请稍后重试。' >&2
    exit 68
fi
trap '/bin/rmdir "$lock"' EXIT
staging=$(/usr/bin/mktemp -d "$target_dir/.Rimo-install.XXXXXXXX")
cleanup() {
    if [[ ! -e "$target" && -e "$staging/previous.driver" ]]; then
        /bin/mv "$staging/previous.driver" "$target"
    fi
    /bin/rm -rf "$staging"
    /bin/rmdir "$lock"
}
trap cleanup EXIT
/usr/bin/ditto --norsrc --noextattr --qtn "$source_driver" "$staging/RimoMicrophone.driver"
/usr/sbin/chown -R root:wheel "$staging/RimoMicrophone.driver"
/bin/chmod -R go-w "$staging/RimoMicrophone.driver"
/usr/bin/codesign --verify --strict "$staging/RimoMicrophone.driver"
# Keep the previous bundle until the replacement is in place.
if [[ -e "$target" ]]; then /bin/mv "$target" "$staging/previous.driver"; fi
if ! /bin/mv "$staging/RimoMicrophone.driver" "$target"; then
    if [[ -e "$staging/previous.driver" ]]; then /bin/mv "$staging/previous.driver" "$target"; fi
    exit 67
fi
# Preserve active calls/recordings: do not restart coreaudiod automatically.
