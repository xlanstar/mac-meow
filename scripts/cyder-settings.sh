#!/bin/bash
# Cyder 全域設定（settings.json）：wineLocale、graphicsBackend、graphicsHud、msync、esync。
# Cyder 只在「直接啟動 MapleStory.exe」時套用楓之谷設定；經由登入器啟動時要改成全域設定，子程序才會繼承。
# 同步機制預設 MSync（Cyder 預設關閉，此時每次同步都經 wineserver，楓之谷會明顯卡頓）。
# 圖形後端預設 D3DMetal；無法使用時（macOS 14 以下或沒有 GPTK）改寫 DXMT，
# 否則 Cyder 會退回 Wine 內建的 wined3d（docs/technical-notes.md #13）。
#
# 第一次修改前把原檔備份為 settings.json.macmeow-orig（已有備份就保留，備份即最初的原值）。
#
# 用法：bash scripts/cyder-settings.sh check|apply|restore
#   check    設定都符合則回傳 0（依 MAPLE_SYNC、MAPLE_GFX、MAPLE_HUD）
#   apply    寫入不符合的設定
#   restore  把上述設定還原成備份中的原值並刪除備份；目前值已不是本專案會寫入的值（使用者事後改過）就保留
# 環境變數：MAPLE_SYNC=msync|esync|none（預設 msync）、MAPLE_GFX=d3dmetal|dxmt（預設 d3dmetal）、
#           MAPLE_HUD=0|1（預設 0；1 為 Metal 效能 HUD）
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

case "${MAPLE_GFX:-d3dmetal}" in
  d3dmetal | dxmt) want_gfx="${MAPLE_GFX:-d3dmetal}" ;;
  *) die "MAPLE_GFX 只能是 d3dmetal|dxmt" ;;
esac

case "${MAPLE_HUD:-0}" in
  0) want_hud=off ;;
  1) want_hud=metal ;;
  *) die "MAPLE_HUD 只能是 0|1" ;;
esac

# 每行「key 型別 本專案可能寫入的值」；多個值以 | 分隔（依環境變數而定）。
# restore 以此判斷目前值是否仍是本專案寫入的。
SPEC="wineLocale string zh_TW
graphicsBackend string dxmt|d3dmetal
graphicsHud string off|metal
msync bool true|false
esync bool true|false"

# 選了 D3DMetal 但無法使用時改用 DXMT（只在 check／apply 檢查；restore 不需要）。
gfx_fallback=0
resolve_gfx() {
  if [[ "$want_gfx" == d3dmetal ]] && ! d3dmetal_available; then
    want_gfx=dxmt gfx_fallback=1
  fi
  return 0
}

want() {
  case "$1" in
    graphicsBackend) echo "$want_gfx" ;;
    graphicsHud) echo "$want_hud" ;;
    msync) echo "$want_msync" ;;
    esync) echo "$want_esync" ;;
    *) echo "$SPEC" | /usr/bin/awk -v k="$1" '$1 == k { print $3 }' ;;
  esac
}

# ours <可能寫入的值> <目前值>：目前值是本專案可能寫入的值之一。
ours() { [[ "|$1|" == *"|$2|"* ]]; }

# 輸出不符合的 key
mismatched() {
  local key _t _v
  while read -r key _t _v; do
    [[ "$(cyder_setting "$key")" == "$(want "$key")" ]] || echo "$key"
  done <<<"$SPEC"
}

case "${1:-}" in
  check)
    resolve_gfx
    [[ -z "$(mismatched)" ]]
    ;;
  apply)
    resolve_gfx
    ((gfx_fallback)) && echo "注意：D3DMetal 無法使用（需要 macOS 14 以上，並安裝 CrossOver 或在 Cyder 設定安裝 GPTK），改用 DXMT"
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
    engine_running && echo "注意：Cyder 正在執行，設定要等全部遊戲關閉後才會生效"
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
    while read -r key type values; do
      cur="$(cyder_setting "$key")"
      if orig="$(/usr/bin/plutil -extract "$key" raw -o - "$BAK" 2>/dev/null)"; then
        [[ "$cur" == "$orig" ]] && continue
        if ! ours "$values" "$cur"; then
          echo "Cyder 設定：${key} 已被改成 ${cur}，保留"
          continue
        fi
        /usr/bin/plutil -replace "$key" "-$type" "$orig" "$CYDER_SETTINGS"
        echo "Cyder 設定：${key} 已還原為 ${orig}"
      else
        /usr/bin/plutil -extract "$key" raw -o - "$CYDER_SETTINGS" >/dev/null 2>&1 || continue
        if ! ours "$values" "$cur"; then
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
