#!/bin/bash
# Cyder 設定（settings.json）：全域的 wineLocale、graphicsBackend、graphicsHud、dxvkFrameRate、msync、esync，
# 以及 認證器.exe 的 perProfile 環境變數 D3DM_MAX_FPS。
# Cyder 只在「直接啟動 MapleStory.exe」時套用楓之谷設定；經由登入器啟動時要改成全域設定，子程序才會繼承。
# 同步機制預設 MSync（Cyder 預設關閉，此時每次同步都經 wineserver，楓之谷會明顯卡頓）。
# 圖形後端預設 D3DMetal；無法使用時（macOS 14 以下或沒有 GPTK）改寫 DXMT，
# 否則 Cyder 會退回 Wine 內建的 wined3d（docs/technical-notes.md #13）。
# FPS 上限：Cyder 的 dxvkFrameRate 只套用到 DXVK／DXMT，D3DMetal 改由 D3DM_MAX_FPS 限制；Cyder 不設這個變數，
# 所以寫進 認證器.exe 的 perProfile.<id>.environment，由 Wine 傳給登入器與 MapleStory.exe（#13）。
#
# 第一次修改前把原檔備份為 settings.json.macmeow-orig（已有備份就保留，備份即最初的原值）。
#
# 用法：bash scripts/cyder-settings.sh check|apply|restore
#   check    設定都符合則回傳 0（依 MAPLE_SYNC、MAPLE_GFX、MAPLE_HUD、MAPLE_FPS）
#   apply    寫入不符合的設定
#   restore  把上述設定還原成備份中的原值並刪除備份；目前值已不是本專案會寫入的值（使用者事後改過）就保留
# 環境變數：MAPLE_SYNC=msync|esync|none（預設 msync）、MAPLE_GFX=d3dmetal|dxmt（預設 d3dmetal）、
#           MAPLE_HUD=0|1（預設 0；1 為 Metal 效能 HUD）、MAPLE_FPS=60|120|144|unlimited（預設 unlimited）
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

# dxvkFrameRate 的值與 Cyder App 寫入的相同（sixty|120|144|unlimited）；D3DM_MAX_FPS 為空表示不設（移除）。
case "${MAPLE_FPS:-unlimited}" in
  60) want_fps=sixty want_d3dm=60 ;;
  120 | 144) want_fps="$MAPLE_FPS" want_d3dm="$MAPLE_FPS" ;;
  unlimited) want_fps=unlimited want_d3dm="" ;;
  *) die "MAPLE_FPS 只能是 60|120|144|unlimited" ;;
esac

# 認證器.exe 的 D3DM_MAX_FPS（plutil keypath）；遊戲資料夾沒有 認證器.exe 時不處理。
D3DM_SUFFIX="environment.D3DM_MAX_FPS"
D3DM_VALUES="60|120|144"
d3dm_key=""
if profile="$(cyder_profile_id "$GAME_DIR/認證器.exe")"; then
  d3dm_key="perProfile.$profile.$D3DM_SUFFIX"
fi

# 每行「key 型別 本專案可能寫入的值」；多個值以 | 分隔（依環境變數而定）。
# restore 以此判斷目前值是否仍是本專案寫入的。
SPEC="wineLocale string zh_TW
graphicsBackend string dxmt|d3dmetal
graphicsHud string off|metal
dxvkFrameRate string sixty|120|144|unlimited
msync bool true|false
esync bool true|false"
[[ -n "$d3dm_key" ]] && SPEC="$SPEC
$d3dm_key string $D3DM_VALUES"

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
    dxvkFrameRate) echo "$want_fps" ;;
    msync) echo "$want_msync" ;;
    esync) echo "$want_esync" ;;
    "$d3dm_key") echo "$want_d3dm" ;;
    *) echo "$SPEC" | /usr/bin/awk -v k="$1" '$1 == k { print $3 }' ;;
  esac
}

# ours <可能寫入的值> <目前值>：目前值是本專案可能寫入的值之一。
ours() { [[ "|$1|" == *"|$2|"* ]]; }

has_key() { /usr/bin/plutil -extract "$1" raw -o - "$2" >/dev/null 2>&1; }
is_dict() { /usr/bin/plutil -extract "$1" json -o - "$CYDER_SETTINGS" 2>/dev/null | /usr/bin/grep -q '^{'; }

# ensure_parents <keypath>：建立 keypath 上層不存在的字典（perProfile.<id>.environment）。
ensure_parents() {
  local path="" part rest="${1%.*}"
  [[ "$rest" == "$1" ]] && return 0
  while [[ -n "$rest" ]]; do
    part="${rest%%.*}"
    if [[ "$part" == "$rest" ]]; then rest=""; else rest="${rest#*.}"; fi
    path="${path:+$path.}$part"
    is_dict "$path" || /usr/bin/plutil -insert "$path" -dictionary "$CYDER_SETTINGS"
  done
}

# remove_key <keypath>：移除 key，並由內而外刪除因此變空的上層字典。
remove_key() {
  local path="$1"
  /usr/bin/plutil -remove "$path" "$CYDER_SETTINGS"
  while [[ "$path" == *.* ]]; do
    path="${path%.*}"
    [[ "$(/usr/bin/plutil -extract "$path" json -o - "$CYDER_SETTINGS" 2>/dev/null)" == "{}" ]] || break
    /usr/bin/plutil -remove "$path" "$CYDER_SETTINGS"
  done
}

# 輸出不符合的 key
mismatched() {
  local key _t _v
  while read -r key _t _v; do
    [[ "$(cyder_setting "$key")" == "$(want "$key")" ]] || echo "$key"
  done <<<"$SPEC"
}

# restore_key <key> <型別> <本專案可能寫入的值>
restore_key() {
  local key="$1" type="$2" values="$3" cur orig
  cur="$(cyder_setting "$key")"
  if orig="$(/usr/bin/plutil -extract "$key" raw -o - "$BAK" 2>/dev/null)"; then
    [[ "$cur" == "$orig" ]] && return 0
    if ! ours "$values" "$cur"; then
      echo "Cyder 設定：${key} 已被改成 ${cur}，保留"
      return 0
    fi
    ensure_parents "$key"
    /usr/bin/plutil -replace "$key" "-$type" "$orig" "$CYDER_SETTINGS"
    echo "Cyder 設定：${key} 已還原為 ${orig}"
  else
    has_key "$key" "$CYDER_SETTINGS" || return 0
    if ! ours "$values" "$cur"; then
      echo "Cyder 設定：${key} 已被改成 ${cur}，保留"
      return 0
    fi
    remove_key "$key"
    echo "Cyder 設定：${key} 已還原（移除）"
  fi
}

# 目前 settings.json 中有 D3DM_MAX_FPS 的 profile key（遊戲資料夾搬移過時，舊路徑的 profile 也要還原）。
d3dm_keys() {
  local id
  /usr/bin/plutil -extract perProfile xml1 -o - "$CYDER_SETTINGS" 2>/dev/null \
    | LC_ALL=C /usr/bin/sed -nE 's|.*<key>(profile-[0-9a-f]{24})</key>.*|\1|p' | while read -r id; do
    has_key "perProfile.$id.$D3DM_SUFFIX" "$CYDER_SETTINGS" && echo "perProfile.$id.$D3DM_SUFFIX"
  done
  return 0
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
      if [[ -z "$value" ]]; then
        remove_key "$key"
        echo "已設定 Cyder：移除 ${key}"
        continue
      fi
      ensure_parents "$key"
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
      [[ "$key" == "$d3dm_key" ]] && continue # 下面與其他 profile 一起處理
      restore_key "$key" "$type" "$values"
    done <<<"$SPEC"
    keys="$(
      d3dm_keys
      [[ -n "$d3dm_key" ]] && echo "$d3dm_key"
      true
    )"
    for key in $(echo "$keys" | /usr/bin/sort -u); do
      restore_key "$key" string "$D3DM_VALUES"
    done
    rm -f "$BAK"
    ;;
  *)
    echo "用法：$0 check|apply|restore" >&2
    exit 64
    ;;
esac
