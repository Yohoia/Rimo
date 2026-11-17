#!/bin/bash
set -euo pipefail
resource_dir="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"
/bin/mkdir -p "$resource_dir"
packaged_app="$resource_dir/PacketLogger.app"
if source_app=$(/bin/bash "$SRCROOT/scripts/packetlogger-path.sh"); then
    if [[ ! "$source_app" -ef "$packaged_app" ]]; then
        /bin/rm -rf -- "$packaged_app"
        /usr/bin/ditto --norsrc --noextattr --qtn "$source_app" "$packaged_app"
    fi
    /usr/bin/codesign --verify --deep --strict -R='anchor apple and identifier "com.apple.PacketLogger"' "$packaged_app"
else
    status=$?
    if [[ $status -ne 1 ]]; then exit "$status"; fi
    /bin/rm -rf -- "$packaged_app"
    echo 'note: PacketLogger not found; building Rimo without Bluetooth voice capture.'
fi
/bin/cp "$SRCROOT/Rimo/Resources/capture-voice.sh" "$resource_dir/capture-voice.sh"
/bin/cp "$SRCROOT/Rimo/Resources/Opus-LICENSE.txt" "$resource_dir/Opus-LICENSE.txt"

/bin/bash "$SRCROOT/scripts/build-audio-driver.sh" "$resource_dir"
/bin/cp "$SRCROOT/Rimo/Resources/install-microphone.sh" "$resource_dir/install-microphone.sh"
