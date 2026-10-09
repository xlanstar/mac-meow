#!/bin/bash
# 遊戲資料夾的 macOS 下載隔離標記（com.apple.quarantine）。只動 xattr，不動檔案內容。
#
# 移除前把每個檔案原本的標記記錄到 ~/Library/Application Support/MacMeow/quarantine.macmeow-orig
# （每行「標記值<TAB>絕對路徑」，多次移除時附加）。
#
# 用法：bash scripts/quarantine.sh check|apply|restore
#   check    遊戲資料夾內沒有隔離標記則回傳 0
#   apply    記錄並移除遊戲資料夾內的隔離標記
#   restore  把記錄的標記加回仍存在的檔案，並刪除記錄
# 遊戲資料夾：common.sh 的 GAME_DIR
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

ATTR=com.apple.quarantine
BAK="$MACMEOW_SUPPORT/quarantine.macmeow-orig"
has_quarantine() {
  [[ -n "$(/usr/bin/find "$GAME_DIR" -xattrname "$ATTR" -print -quit 2>/dev/null)" ]]
}

cmd_check() { ! has_quarantine; }

cmd_apply() {
  local tmp="$BAK.tmp" count
  [[ -d "$GAME_DIR" ]] || die "找不到遊戲資料夾：${GAME_DIR}"
  has_quarantine || return 0
  /bin/mkdir -p "$MACMEOW_SUPPORT"
  # xattr -r -p 輸出「路徑: 標記值」；標記值（旗標;時間;App;UUID）不含「: 」，所以以最後一個「: 」切開。
  # 只有完整記錄後才移除標記。
  /usr/bin/xattr -r -p "$ATTR" "$GAME_DIR" 2>/dev/null | LC_ALL=C /usr/bin/awk '
    {
      n = 0; s = $0
      while ((i = index(s, ": ")) > 0) { n += i + 1; s = substr(s, i + 2) }
      if (n > 0) printf "%s\t%s\n", s, substr($0, 1, n - 2)
    }' >"$tmp" || true
  [[ -s "$tmp" ]] || {
    rm -f "$tmp"
    die "無法讀取遊戲資料夾的隔離標記，不移除"
  }
  count="$(/usr/bin/wc -l <"$tmp" | /usr/bin/tr -d ' ')"
  /bin/cat "$tmp" >>"$BAK" && rm -f "$tmp"
  /usr/bin/xattr -dr "$ATTR" "$GAME_DIR" 2>/dev/null || true
  echo "已移除 ${count} 個項目的下載隔離標記（記錄於 ${BAK}）"
}

cmd_restore() {
  local value
  [[ -f "$BAK" ]] || {
    echo "下載隔離標記：無記錄"
    return 0
  }
  # 同一標記值的檔案以一次 xattr 寫回；已不存在的檔案 xattr 會略過（回傳非 0）。
  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    VALUE="$value" LC_ALL=C /usr/bin/awk -F '\t' '$1 == ENVIRON["VALUE"] { print substr($0, length($1) + 2) }' "$BAK" \
      | /usr/bin/tr '\n' '\0' | /usr/bin/xargs -0 /usr/bin/xattr -w "$ATTR" "$value" 2>/dev/null || true
  done < <(/usr/bin/cut -f1 "$BAK" | LC_ALL=C /usr/bin/sort -u)
  rm -f "$BAK"
  echo "下載隔離標記：已加回"
}

case "${1:-}" in
  check | apply | restore) "cmd_$1" ;;
  *) usage "check|apply|restore" ;;
esac
