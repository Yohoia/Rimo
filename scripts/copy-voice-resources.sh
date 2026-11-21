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
/bin/rm -f "$resource_dir/capture-voice.sh"
/bin/cp "$SRCROOT/Rimo/Resources/Opus-LICENSE.txt" "$resource_dir/Opus-LICENSE.txt"

/bin/bash "$SRCROOT/scripts/build-audio-driver.sh" "$resource_dir"
/bin/cp "$SRCROOT/Rimo/Resources/install-microphone.sh" "$resource_dir/install-microphone.sh"

# Build the fixed-operation environment tool for both supported Mac architectures.
environment_build="$TARGET_TEMP_DIR/voice-environment"
/bin/mkdir -p "$environment_build"
for architecture in arm64 x86_64; do
    /usr/bin/xcrun swiftc -swift-version 6 -O -target "$architecture-apple-macos13.0" \
        "$SRCROOT/Rimo/VoiceTools/VoiceEnvironment.swift" \
        -o "$environment_build/$architecture"
done
/usr/bin/lipo -create "$environment_build/arm64" "$environment_build/x86_64" \
    -output "$resource_dir/voice-environment"
/usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --timestamp=none "$resource_dir/voice-environment"

# The helper ships inside the app but runs only after deploy-voice.sh copies it
# into a root-owned directory and registers it with launchd.
helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/HelperTools"
/bin/rm -rf "$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Library/LaunchDaemons"
/bin/mkdir -p "$helper_dir"
for architecture in arm64 x86_64; do
    /usr/bin/xcrun swiftc -swift-version 6 -O -parse-as-library -target "$architecture-apple-macos13.0" \
        "$SRCROOT/Rimo/VoiceHelper/VoiceHelperProtocol.swift" \
        "$SRCROOT/Rimo/VoiceHelper/VoiceHelperMain.swift" -o "$environment_build/helper-$architecture"
done
/usr/bin/lipo -create "$environment_build/helper-arm64" "$environment_build/helper-x86_64" \
    -output "$helper_dir/RimoVoiceHelper"
/usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY:--}" --identifier cn.yohoia.rimo.voice-helper --timestamp=none "$helper_dir/RimoVoiceHelper"
/bin/cp "$SRCROOT/Rimo/Resources/deploy-voice.sh" "$resource_dir/deploy-voice.sh"

# Rimo redeploys (one administrator prompt) only when this fingerprint changes.
/usr/bin/shasum -a 256 \
    "$helper_dir/RimoVoiceHelper" "$resource_dir/voice-environment" \
    "$resource_dir/install-microphone.sh" "$resource_dir/deploy-voice.sh" \
    "$resource_dir/RimoMicrophone.driver/Contents/MacOS/RimoMicrophone" \
    "$resource_dir/RimoMicrophone.driver/Contents/Info.plist" \
    | /usr/bin/awk '{print $1}' | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}' \
    > "$resource_dir/voice-deployment-id"
