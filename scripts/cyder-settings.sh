#!/bin/bash
# Cyder 全域設定（settings.json）：wineLocale、graphicsBackend、msync、esync。
# Cyder 只在「直接啟動 MapleStory.exe」時套用楓之谷設定；經由登入器啟動時要改成全域設定，子程序才會繼承。
# 同步機制預設 MSync（Cyder 預設關閉，此時每次同步都經 wineserver，楓之谷會明顯卡頓）。
#
# 第一次修改前把原檔備份為 settings.json.macmeow-orig（已有備份就保留，備份即最初的原值）。
#
# 用法：bash scripts/cyder-settings.sh check|apply|restore
#   check    設定都符合則回傳 0（同步機制依 MAPLE_SYNC）
#   apply    寫入不符合的設定
#   restore  把上述設定還原成備份中的原值並刪除備份；目前值已不是本專案寫入的值（使用者事後改過）就保留
# 環境變數：MAPLE_SYNC=msync|esync|none（預設 msync）
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

BAK="$CYDER_SETTINGS.macmeow-orig"

case "${MAPLE_SYNC:-msync}" in
  msync) want_msync=true want_esync=false ;;
  esync) want_msync=false want_esync=true ;;
  none) want_msync=false want_esync=false ;;
  *) die "MAPLE_SYNC 只能是 msync|esync|none" ;;
esac

# 每行「key 型別 本專案寫入的值」；值為 * 表示可能寫入任何值（依 MAPLE_SYNC）。
SPEC="wineLocale string zh_TW
graphicsBackend string dxmt
msync bool *
esync bool *"

want() {
  case "$1" in
    msync) echo "$want_msync" ;;
    esync) echo "$want_esync" ;;
    *) echo "$SPEC" | /usr/bin/awk -v k="$1" '$1 == k { print $3 }' ;;
  esac
}

# 輸出不符合的 key
mismatched() {
  local key _t _v
  while read -r key _t _v; do
    [[ "$(cyder_setting "$key")" == "$(want "$key")" ]] || echo "$key"
  done <<<"$SPEC"
}

case "${1:-}" in
  check)
    [[ -z "$(mismatched)" ]]
    ;;
  apply)
    keys="$(mismatched)"
    [[ -n "$keys" ]] || exit 0
    if [[ ! -f "$BAK" ]]; then
      if [[ -f "$CYDER_SETTINGS" ]]; then cp -p "$CYDER_SETTINGS" "$BAK"; else echo '{}' >"$BAK"; fi
    fi
    [[ -f "$CYDER_SETTINGS" ]] || echo '{"schemaVersion":1}' >"$CYDER_SETTINGS"
    for key in $keys; do
      type="$(echo "$SPEC" | /usr/bin/awk -v k="$key" '$1 == k { print $2 }')"
      value="$(want "$key")"
      /usr/bin/plutil -replace "$key" "-$type" "$value" "$CYDER_SETTINGS"
      echo "已設定 Cyder：${key}=${value}"
    done
    wine_running && echo "注意：Cyder 正在執行，設定要等全部遊戲關閉後才會生效"
    exit 0
    ;;
  restore)
    [[ -f "$BAK" ]] || {
      echo "Cyder 設定：無備份"
      exit 0
    }
    [[ -f "$CYDER_SETTINGS" ]] || {
      echo "Cyder 設定：找不到 settings.json，只刪除備份"
      rm -f "$BAK"
      exit 0
    }
    while read -r key type ours; do
      cur="$(cyder_setting "$key")"
      if orig="$(/usr/bin/plutil -extract "$key" raw -o - "$BAK" 2>/dev/null)"; then
        [[ "$cur" == "$orig" ]] && continue
        if [[ "$ours" != "*" && "$cur" != "$ours" ]]; then
          echo "Cyder 設定：${key} 已被改成 ${cur}，保留"
          continue
        fi
        /usr/bin/plutil -replace "$key" "-$type" "$orig" "$CYDER_SETTINGS"
        echo "Cyder 設定：${key} 已還原為 ${orig}"
      else
        /usr/bin/plutil -extract "$key" raw -o - "$CYDER_SETTINGS" >/dev/null 2>&1 || continue
        if [[ "$ours" != "*" && "$cur" != "$ours" ]]; then
          echo "Cyder 設定：${key} 已被改成 ${cur}，保留"
          continue
        fi
        /usr/bin/plutil -remove "$key" "$CYDER_SETTINGS"
        echo "Cyder 設定：${key} 已還原（移除）"
      fi
    done <<<"$SPEC"
    rm -f "$BAK"
    ;;
  *)
    echo "用法：$0 check|apply|restore" >&2
    exit 64
    ;;
esac
