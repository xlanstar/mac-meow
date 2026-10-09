#!/bin/bash
# 關閉 Cyder（CrossOver）wineserver 的「bind 127.x.x.x 一律改成 127.0.0.1」HACK（docs/technical-notes.md #2）。
# setup-loopback.sh 已替 lo0 加上真正的位址，因此可以安全關閉。
#
# 只改 wineserver 一個位元組（jne → jmp）並重新 ad-hoc 簽章；原檔備份為 wineserver.macmeow-orig。
# Cyder 更新 engine 後 play.sh 會重新套用。
#
# 用法：bash scripts/patch-cyder-loopback.sh check|apply|restore
#   check    已套用則回傳 0
#   apply    套用（Wine 執行中會拒絕）
#   restore  還原並刪除備份（Wine 執行中會拒絕）
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

WS="$WINESERVER_BIN"
BAK="$WS.macmeow-orig"

# cmpl $0x100007f,%r13d ; sete %cl ; orb %al,%cl ; 後面接 jne/jmp rel8
PATTERN=4181fd7f0000010f94c108c1

# 輸出「偏移 目前位元組」；序列找不到或不唯一時輸出「ERR 次數」。以 xxd 搜尋（macOS 內建）。
find_offset() {
  local hex h n=0 pos=-1
  hex="$(/usr/bin/xxd -p "$WS" | /usr/bin/tr -d '\n')"
  for h in $(printf '%s' "$hex" | /usr/bin/grep -bo "$PATTERN" | /usr/bin/cut -d: -f1); do
    ((h % 2 == 0)) && {
      n=$((n + 1))
      pos=$h
    } # 只接受位元組對齊的命中
  done
  ((n == 1)) || {
    echo "ERR $n"
    return 0
  }
  local off=$(((pos + ${#PATTERN}) / 2))
  echo "$off ${hex:$((off * 2)):2}"
}

# 輸出 patched|unpatched|unknown
state() {
  local off op
  read -r off op < <(find_offset)
  case "$op" in
    75) echo unpatched ;;
    eb) echo patched ;;
    *) echo unknown ;;
  esac
}

[[ -f "$WS" ]] || die "找不到 Cyder engine：${WS}（請先開一次 Cyder）"

case "${1:-}" in
  check)
    s="$(state)"
    echo "wineserver loopback 修補：$s"
    [[ "$s" == patched ]]
    ;;
  apply)
    s="$(state)"
    [[ "$s" == patched ]] && {
      echo "wineserver loopback 修補：已套用"
      exit 0
    }
    [[ "$s" == unpatched ]] || die "wineserver 找不到預期的指令序列（Cyder engine 版本不同？），不修改。"
    require_wine_stopped "套用 wineserver 修補"
    read -r off _ < <(find_offset)
    cp -p "$WS" "$BAK" # 目前檔案是未修補的原檔（含 engine 更新後的新版），一律更新備份
    printf '\xeb' | /bin/dd of="$WS" bs=1 seek="$off" conv=notrunc status=none
    /usr/bin/codesign --force --sign - --preserve-metadata=entitlements "$WS" 2>/dev/null \
      || /usr/bin/codesign --force --sign - "$WS"
    [[ "$(state)" == patched ]] || {
      cp -p "$BAK" "$WS"
      die "套用後驗證失敗，已還原。"
    }
    echo "wineserver loopback 修補：已套用（offset ${off}，原檔備份 ${BAK}）"
    ;;
  restore)
    [[ -f "$BAK" ]] || {
      echo "wineserver loopback 修補：無備份"
      exit 0
    }
    require_wine_stopped "還原 wineserver"
    if [[ "$(state)" == patched ]]; then
      cp -p "$BAK" "$WS"
      echo "wineserver loopback 修補：已還原"
    else
      echo "wineserver loopback 修補：目前不是修補版（engine 已更新？），只刪除過期備份"
    fi
    rm -f "$BAK"
    ;;
  *)
    echo "用法：$0 check|apply|restore" >&2
    exit 64
    ;;
esac
