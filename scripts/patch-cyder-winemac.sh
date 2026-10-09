#!/bin/bash
# 讓 Cyder 的 winemac.so 可以依程式隱藏 Dock 圖示（docs/technical-notes.md #10）。
# 修補後，AppDefaults\<exe>\Mac Driver 設了 CaptureDisplaysForFullscreen=y 的程式會成為「輔助程式」
# （NSApplicationActivationPolicyAccessory：沒有 Dock 圖示與縮到 Dock 的視窗，視窗仍可點擊、輸入）；
# 其他程式行為不變。設定值由 launcher-dock.sh 寫入，只套用到登入器。
#
# Cyder 的 winemac.so 含 Cyder 自己的楓之谷修補（原始碼未公開），不能以 CrossOver 原始碼重建取代，
# 因此只改 -[WineApplicationController transformProcessToForeground:] 內兩段指令並重新 ad-hoc 簽章：
#   0x5221  testq %rax,%rax; je → cmpb $2,%al; jne     「已轉成前景程式」改為「已不是 Prohibited」
#   0x529e  setActivationPolicy:0 → setActivationPolicy:capture_displays_for_fullscreen（0 或 1）
# 只套用到已知的 winemac.so（SHA-256 相符）；其他版本不修改。原檔備份為 winemac.so.macmeow-orig。
#
# 用法：bash scripts/patch-cyder-winemac.sh check|apply|restore
#   check    已套用則回傳 0
#   apply    套用（Wine 執行中會拒絕；engine 版本不同時回傳 2，不修改）
#   restore  還原並刪除備份（Wine 執行中會拒絕）
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

PATCH_FILE="$CYDER_ENGINE/lib/wine/x86_64-unix/winemac.so"
PATCH_LABEL="winemac Dock 圖示修補"
# shellcheck source=lib/engine-patch.sh
source "$MACMEOW_SCRIPTS/lib/engine-patch.sh"

# Cyder engine CX26.3.0-W11-Cyder012 的 winemac.so
KNOWN_SHA256=6691e1ab75e16891ba332e5a6847ebab7a5884ca472c374054ce4e6c914f5e64

# 修補段：偏移（十進位）、原始位元組、修補後位元組
A_OFF=$((0x5221))
A_ORIG=4885c074d5
A_NEW=3c0275d690
B_OFF=$((0x529e))
B_ORIG=488b057bed0400488b38488b35c19c050031d2ff1511ef04004584ff7416488b35a59c0500488b7dc8ba01000000ff15f6ee0400
B_NEW=488b057bed0400488b38488b35c19c05000fb6150ad5050041ffd44584ff7414488b35a39c0500488b7dc8ba0100000041ffd490

bytes_at() { /usr/bin/xxd -s "$1" -l "$2" -p "$PATCH_FILE" | /usr/bin/tr -d '\n'; }
write_hex() { printf '%s' "$2" | /usr/bin/xxd -r -p | /bin/dd of="$PATCH_FILE" bs=1 seek="$1" conv=notrunc status=none; }

patch_state() {
  local a b
  a="$(bytes_at "$A_OFF" $((${#A_ORIG} / 2)))"
  b="$(bytes_at "$B_OFF" $((${#B_ORIG} / 2)))"
  if [[ "$a" == "$A_NEW" && "$b" == "$B_NEW" ]]; then
    echo patched
  elif [[ "$a" == "$A_ORIG" && "$b" == "$B_ORIG" && "$(sha256 "$PATCH_FILE")" == "$KNOWN_SHA256" ]]; then
    echo unpatched
  else
    echo unknown
  fi
}

patch_write() {
  write_hex "$A_OFF" "$A_NEW"
  write_hex "$B_OFF" "$B_NEW"
}

patch_main "$@"
