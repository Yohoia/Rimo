#!/bin/bash
# One administrator authorization deploys every root-side voice component:
# the XPC service, Bluetooth capture configuration and the virtual microphone.
# Everything root executes is copied into root-owned locations first, so later
# capture sessions never run code from the user-writable application bundle.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo '需要管理员授权。' >&2; exit 64; }

label=cn.yohoia.rimo.voice-service
legacy_label=cn.yohoia.rimo.voice-helper
parent='/Library/Application Support/Rimo'
target="$parent/VoiceService"
daemon="/Library/LaunchDaemons/$label.plist"
driver=/Library/Audio/Plug-Ins/HAL/RimoMicrophone.driver

fail() { echo "$1" >&2; exit "${2:-1}"; }
bundle_id() { /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null || true; }
bundle_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist" 2>/dev/null || true; }

stop_services() {
    /bin/launchctl bootout "system/$label" 2>/dev/null || true
    # Builds before this script registered the helper through SMAppService.
    /bin/launchctl bootout "system/$legacy_label" 2>/dev/null || true
}

if [[ ${1:-} == --uninstall ]]; then
    [[ $# -eq 1 ]] || exit 64
    stop_services
    /bin/rm -f "$daemon"
    if [[ -x "$target/voice-environment" ]] &&
       "$target/voice-environment" status | /usr/bin/grep -q '"canRestore":true'; then
        "$target/voice-environment" restore >/dev/null
    fi
    if [[ -e "$driver" && $(bundle_id "$driver") == cn.yohoia.rimo.audio ]]; then
        /bin/rm -rf "$driver"
        /usr/bin/killall coreaudiod 2>/dev/null || true
    fi
    /bin/rm -rf "$target"
    exit 0
fi

[[ $# -eq 1 ]] || exit 64
app=$1
contents="$app/Contents"
resources="$contents/Resources"
[[ -d "$contents" ]] || fail '找不到 Rimo 应用。' 65
# Not --strict: synced folders (iCloud Desktop) add Finder xattrs to the bundle.
# Every component root will execute is copied without xattrs and verified strictly below.
if ! verification=$(/usr/bin/codesign --verify "$app" 2>&1); then
    fail "Rimo 应用签名校验失败：$verification" 65
fi
signature=$(/usr/bin/codesign -dv "$app" 2>&1)
[[ $(/usr/bin/sed -n 's/^Identifier=//p' <<<"$signature") == cn.yohoia.rimo ]] || fail '只能安装 Rimo 自带的语音组件。' 65
[[ -d "$resources/PacketLogger.app" ]] || fail '此 Rimo 构建没有包含 PacketLogger，无法启用语音。' 65

# Bind the service to this team, or to this exact build for ad-hoc signatures.
team=$(/usr/bin/sed -n 's/^TeamIdentifier=//p' <<<"$signature")
if [[ -n $team && $team != 'not set' ]]; then
    requirement="identifier \"cn.yohoia.rimo\" and anchor apple generic and certificate leaf[subject.OU] = \"$team\""
else
    requirement=$(/usr/bin/codesign -d -r- "$app" 2>&1 | /usr/bin/sed -n 's/^#* *designated => //p')
fi
[[ -n $requirement ]] || fail '无法读取 Rimo 签名要求。' 65

/bin/mkdir -p "$parent"
/usr/sbin/chown root:wheel "$parent"
/bin/chmod 755 "$parent"
staging=$(/usr/bin/mktemp -d "$parent/.VoiceService.XXXXXXXX")
trap '/bin/rm -rf "$staging" "$staging.previous"' EXIT

copy() { /usr/bin/ditto --norsrc --noextattr "$1" "$staging/$2"; }
copy "$contents/Library/HelperTools/RimoVoiceHelper" RimoVoiceHelper
copy "$resources/voice-environment" voice-environment
copy "$resources/install-microphone.sh" install-microphone.sh
copy "$resources/RimoMicrophone.driver" RimoMicrophone.driver
copy "$resources/PacketLogger.app" PacketLogger.app
copy "$resources/voice-deployment-id" deployment-id
printf '%s' "$requirement" >"$staging/client-requirement"
/usr/sbin/chown -R root:wheel "$staging"
/bin/chmod -R go-w "$staging"
/bin/chmod 755 "$staging"

verify() { /usr/bin/codesign --verify --strict "$@" 2>/dev/null || fail '语音组件签名校验失败，请重新安装 Rimo。' 66; }
verify -R='identifier "cn.yohoia.rimo.voice-helper"' "$staging/RimoVoiceHelper"
verify "$staging/voice-environment"
verify "$staging/RimoMicrophone.driver"
verify --deep -R='anchor apple and identifier "com.apple.PacketLogger"' "$staging/PacketLogger.app"

stop_services
if [[ -e "$target" ]]; then /bin/mv "$target" "$staging.previous"; fi
/bin/mv "$staging" "$target"

/bin/cat >"$daemon" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>$label</string>
    <key>ProgramArguments</key><array><string>$target/RimoVoiceHelper</string></array>
    <key>MachServices</key><dict><key>$label</key><true/></dict>
    <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
/usr/sbin/chown root:wheel "$daemon"
/bin/chmod 644 "$daemon"
/bin/launchctl enable "system/$label"
# bootout completes asynchronously; retry briefly instead of failing the install.
for attempt in 1 2 3 4 5 6; do
    /bin/launchctl bootstrap system "$daemon" 2>/dev/null && break
    [[ $attempt -eq 6 ]] && fail '语音服务启动失败，请重试。'
    /bin/sleep 0.5
done

if ! "$target/voice-environment" status | /usr/bin/grep -q '"configured":true'; then
    "$target/voice-environment" configure >/dev/null
fi

if [[ $(bundle_version "$target/RimoMicrophone.driver") != "$(bundle_version "$driver")" ]]; then
    /bin/bash "$target/install-microphone.sh" "$target/RimoMicrophone.driver"
    # Reload HAL plug-ins now instead of asking for a Mac restart.
    /usr/bin/killall coreaudiod 2>/dev/null || true
fi
