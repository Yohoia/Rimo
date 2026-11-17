#!/bin/bash
set -euo pipefail
umask 077

here=$(cd -- "$(dirname -- "$0")" && pwd)
project=$(cd -- "$here/../../.." && pwd)
if ! source_app=$(/bin/bash "$project/scripts/packetlogger-path.sh"); then
    echo '缺少 PacketLogger.app。请参阅项目 README 中的可选收音工具配置。' >&2
    exit 1
fi
scratch=$(mktemp -d "${TMPDIR:-/tmp}/Rimo-hci.XXXXXXXX")
app="$scratch/PacketLogger.app"

# Omit Finder metadata on the scratch copy; keep the original and its quarantine policy.
/usr/bin/ditto --norsrc --noextattr --qtn "$source_app" "$app"
/usr/bin/codesign --verify --deep --strict -R='anchor apple and identifier "com.apple.PacketLogger"' "$app"
cli="$app/Contents/Resources/packetlogger"
/usr/bin/codesign --verify --strict -R='anchor apple' "$cli"
if [[ ${1:-} == --check ]]; then
    "$cli" version
    exit
fi
if [[ $# -ne 0 || ! -t 0 || ! -t 1 ]]; then
    echo '请直接在 Terminal 中运行。PacketLogger 需要本机管理员授权。' >&2
    exit 2
fi

trace="$scratch/A2540.pklg"
: > "$trace"
printf '抓包保存在：%s\n' "$trace"
/usr/bin/sudo -v
echo '现在开始采集：先等约 2 秒，再按住 Siri 侧键说约 3 秒。松开后立即按 Control-C 停止。'
trap ':' INT
status=0
/usr/bin/sudo -- "$cli" convert --output "$trace" || status=$?
if [[ -s "$trace" ]]; then
    printf '\n已保存：%s\n' "$trace"
else
    echo '没有采到数据。请保留上方的 PacketLogger 错误文字。' >&2
    exit 1
fi
if [[ $status -ne 0 && $status -ne 130 ]]; then
    exit "$status"
fi
