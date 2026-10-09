#!/bin/bash
# 關閉 Cyder（CrossOver）wineserver 的「bind 127.x.x.x 一律改成 127.0.0.1」HACK（docs/technical-notes.md #2）。
# setup-loopback.sh 已替 lo0 加上真正的位址，因此可以安全關閉。
#
# 只改 wineserver 一個位元組（jne → jmp）並重新 ad-hoc 簽章；原檔備份為 wineserver.macmeow-orig。
# Cyder 更新 engine 後 play.sh 會重新套用。
#
# 用法：bash scripts/patch-cyder-loopback.sh check|apply|restore
#   check    已套用則回傳 0
#   apply    套用（Wine 執行中會拒絕；engine 版本不同時回傳 2，不修改）
#   restore  還原並刪除備份（Wine 執行中會拒絕）
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

PATCH_FILE="$WINESERVER_BIN"
PATCH_LABEL="wineserver loopback 修補"
# shellcheck source=lib/engine-patch.sh
source "$MACMEOW_SCRIPTS/lib/engine-patch.sh"

# cmpl $0x100007f,%r13d ; sete %cl ; orb %al,%cl ; 後面接 jne/jmp rel8
PATTERN=4181fd7f0000010f94c108c1

# 輸出「偏移 目前位元組」；序列找不到或不唯一時輸出「ERR 次數」。以 xxd 搜尋（macOS 內建）。
find_offset() {
  local hex h n=0 pos=-1 off
  hex="$(/usr/bin/xxd -p "$PATCH_FILE" | /usr/bin/tr -d '\n')"
  for h in $(printf '%s' "$hex" | /usr/bin/grep -bo "$PATTERN" | /usr/bin/cut -d: -f1); do
    ((h % 2 == 0)) || continue # 只接受位元組對齊的命中
    n=$((n + 1))
    pos=$h
  done
  ((n == 1)) || {
    echo "ERR $n"
    return 0
  }
  off=$(((pos + ${#PATTERN}) / 2))
  echo "$off ${hex:$((off * 2)):2}"
}

patch_state() {
  local _off op
  read -r _off op < <(find_offset)
  case "$op" in
    75) echo unpatched ;;
    eb) echo patched ;;
    *) echo unknown ;;
  esac
}

# jne → jmp
patch_write() {
  local off _op
  read -r off _op < <(find_offset)
  printf '\xeb' | /bin/dd of="$PATCH_FILE" bs=1 seek="$off" conv=notrunc status=none
}

patch_main "$@"
