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
#   check    設定都符合則回傳 0（依 SYNC、GRAPHICS_BACKEND、HUD、MAX_FPS）
#   apply    寫入不符合的設定
#   restore  把上述設定還原成備份中的原值並刪除備份；目前值已不是本專案會寫入的值（使用者事後改過）就保留
# 環境變數：SYNC=msync|esync|none（預設 msync）、GRAPHICS_BACKEND=d3dmetal|dxmt（預設 d3dmetal）、
#           HUD=0|1（預設 0；1 為 Metal 效能 HUD）、MAX_FPS=60|120|144|unlimited（預設 unlimited）
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

BACKUP="$CYDER_SETTINGS.macmeow-orig"

# ---------- 要寫入的值（want_<設定>） ----------
case "${SYNC:-msync}" in
  msync) want_msync=true want_esync=false ;;
  esync) want_msync=false want_esync=true ;;
  none) want_msync=false want_esync=false ;;
  *) die "SYNC 只能是 msync|esync|none" ;;
esac

case "${GRAPHICS_BACKEND:-d3dmetal}" in
  d3dmetal | dxmt) want_backend="${GRAPHICS_BACKEND:-d3dmetal}" ;;
  *) die "GRAPHICS_BACKEND 只能是 d3dmetal|dxmt" ;;
esac

case "${HUD:-0}" in
  0) want_hud=off ;;
  1) want_hud=metal ;;
  *) die "HUD 只能是 0|1" ;;
esac

# want_dxvk_fps：dxvkFrameRate 的值，與 Cyder App 寫入的相同（sixty|120|144|unlimited）。
# want_d3dm_fps：D3DM_MAX_FPS 的值；空字串表示不設（移除）。
case "${MAX_FPS:-unlimited}" in
  60) want_dxvk_fps=sixty want_d3dm_fps=60 ;;
  120 | 144) want_dxvk_fps="$MAX_FPS" want_d3dm_fps="$MAX_FPS" ;;
  unlimited) want_dxvk_fps=unlimited want_d3dm_fps="" ;;
  *) die "MAX_FPS 只能是 60|120|144|unlimited" ;;
esac

# 認證器.exe 的 D3DM_MAX_FPS（plutil keypath：perProfile.<id>.environment.D3DM_MAX_FPS）；遊戲資料夾沒有 認證器.exe 時不處理。
D3DM_FPS_ENV_PATH="environment.D3DM_MAX_FPS"
# 開頭的空值：unlimited 時本專案會移除這個 key，所以「不存在」也算本專案寫入的狀態（見 is_ours）。
D3DM_FPS_VALUES="|60|120|144"
d3dm_fps_key=""
if profile_id="$(cyder_profile_id "$GAME_DIR/認證器.exe")"; then
  d3dm_fps_key="perProfile.$profile_id.$D3DM_FPS_ENV_PATH"
fi

# 每行「key 型別 本專案可能寫入的值」；多個值以 | 分隔（依環境變數而定），空值表示 key 不存在。
# restore 以此判斷目前值是否仍是本專案寫入的。
SPEC="wineLocale string zh_TW
graphicsBackend string dxmt|d3dmetal
graphicsHud string off|metal
dxvkFrameRate string sixty|120|144|unlimited
msync bool true|false
esync bool true|false"
[[ -n "$d3dm_fps_key" ]] && SPEC="$SPEC
$d3dm_fps_key string $D3DM_FPS_VALUES"

# spec_field <key> <欄位>：SPEC 中該 key 的第 2 欄（型別）或第 3 欄（可能寫入的值）。
spec_field() { echo "$SPEC" | /usr/bin/awk -v k="$1" -v f="$2" '$1 == k { print $f }'; }

# 選了 D3DMetal 但無法使用時改用 DXMT（只在 check／apply 檢查；restore 不需要）。
backend_fallback=0
resolve_backend() {
  if [[ "$want_backend" == d3dmetal ]] && ! d3dmetal_available; then
    want_backend=dxmt backend_fallback=1
  fi
  return 0
}

# wanted_value <key>：本次要寫入的值（空字串表示要移除）。
wanted_value() {
  case "$1" in
    graphicsBackend) echo "$want_backend" ;;
    graphicsHud) echo "$want_hud" ;;
    dxvkFrameRate) echo "$want_dxvk_fps" ;;
    msync) echo "$want_msync" ;;
    esync) echo "$want_esync" ;;
    "$d3dm_fps_key") echo "$want_d3dm_fps" ;;
    *) spec_field "$1" 3 ;;
  esac
}

# is_ours <可能寫入的值> <目前值>：目前值是本專案可能寫入的值之一（值清單有空值時，空的目前值也算）。
is_ours() { [[ "|$1|" == *"|$2|"* ]]; }

setting_exists() { /usr/bin/plutil -extract "$1" raw -o - "$CYDER_SETTINGS" >/dev/null 2>&1; }
setting_is_dict() { /usr/bin/plutil -extract "$1" json -o - "$CYDER_SETTINGS" 2>/dev/null | /usr/bin/grep -q '^{'; }

# ensure_parent_dicts <keypath>：建立 keypath 上層不存在的字典（perProfile.<id>.environment）。
ensure_parent_dicts() {
  local path="" part rest="${1%.*}"
  [[ "$rest" == "$1" ]] && return 0
  while [[ -n "$rest" ]]; do
    part="${rest%%.*}"
    if [[ "$part" == "$rest" ]]; then rest=""; else rest="${rest#*.}"; fi
    path="${path:+$path.}$part"
    setting_is_dict "$path" || /usr/bin/plutil -insert "$path" -dictionary "$CYDER_SETTINGS"
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
mismatched_keys() {
  local key _type _values
  while read -r key _type _values; do
    [[ "$(cyder_setting "$key")" == "$(wanted_value "$key")" ]] || echo "$key"
  done <<<"$SPEC"
}

# restore_key <key> <型別> <本專案可能寫入的值>
restore_key() {
  local key="$1" type="$2" values="$3" cur orig
  cur="$(cyder_setting "$key")"
  if orig="$(/usr/bin/plutil -extract "$key" raw -o - "$BACKUP" 2>/dev/null)"; then
    [[ "$cur" == "$orig" ]] && return 0
    if ! is_ours "$values" "$cur"; then
      echo "Cyder 設定：${key} 已被改成 ${cur}，保留"
      return 0
    fi
    ensure_parent_dicts "$key"
    /usr/bin/plutil -replace "$key" "-$type" "$orig" "$CYDER_SETTINGS"
    echo "Cyder 設定：${key} 已還原為 ${orig}"
  else
    setting_exists "$key" || return 0
    if ! is_ours "$values" "$cur"; then
      echo "Cyder 設定：${key} 已被改成 ${cur}，保留"
      return 0
    fi
    remove_key "$key"
    echo "Cyder 設定：${key} 已還原（移除）"
  fi
}

# 目前 settings.json 中有 D3DM_MAX_FPS 的 profile key（遊戲資料夾搬移過時，舊路徑的 profile 也要還原）。
# 以 raw 列出 perProfile 的 key（字典的 raw 是每行一個 key）；xml1 遇到任何 null 值（JSON 的 null）都會失敗。
d3dm_fps_keys() {
  local id
  /usr/bin/plutil -extract perProfile raw -o - "$CYDER_SETTINGS" 2>/dev/null \
    | LC_ALL=C /usr/bin/grep -E '^profile-[0-9a-f]{24}$' | while read -r id; do
    setting_exists "perProfile.$id.$D3DM_FPS_ENV_PATH" && echo "perProfile.$id.$D3DM_FPS_ENV_PATH"
  done
  return 0
}

case "${1:-}" in
  check)
    resolve_backend
    [[ -z "$(mismatched_keys)" ]]
    ;;
  apply)
    resolve_backend
    ((backend_fallback)) && echo "注意：D3DMetal 無法使用（需要 macOS 14 以上，並安裝 CrossOver 或在 Cyder 設定安裝 GPTK），改用 DXMT"
    keys="$(mismatched_keys)"
    [[ -n "$keys" ]] || exit 0
    if [[ ! -f "$BACKUP" ]]; then
      if [[ -f "$CYDER_SETTINGS" ]]; then cp -p "$CYDER_SETTINGS" "$BACKUP"; else echo '{}' >"$BACKUP"; fi
    fi
    [[ -f "$CYDER_SETTINGS" ]] || echo '{"schemaVersion":1}' >"$CYDER_SETTINGS"
    for key in $keys; do
      value="$(wanted_value "$key")"
      if [[ -z "$value" ]]; then
        remove_key "$key"
        echo "已設定 Cyder：移除 ${key}"
        continue
      fi
      ensure_parent_dicts "$key"
      /usr/bin/plutil -replace "$key" "-$(spec_field "$key" 2)" "$value" "$CYDER_SETTINGS"
      echo "已設定 Cyder：${key}=${value}"
    done
    engine_running && echo "注意：Cyder 正在執行，設定要等全部遊戲關閉後才會生效"
    exit 0
    ;;
  restore)
    [[ -f "$BACKUP" ]] || {
      echo "Cyder 設定：無備份"
      exit 0
    }
    [[ -f "$CYDER_SETTINGS" ]] || {
      echo "Cyder 設定：找不到 settings.json，只刪除備份"
      rm -f "$BACKUP"
      exit 0
    }
    while read -r key type values; do
      [[ "$key" == "$d3dm_fps_key" ]] && continue # 下面與其他 profile 一起處理
      restore_key "$key" "$type" "$values"
    done <<<"$SPEC"
    keys="$(
      d3dm_fps_keys
      [[ -n "$d3dm_fps_key" ]] && echo "$d3dm_fps_key"
      true
    )"
    for key in $(echo "$keys" | /usr/bin/sort -u); do
      restore_key "$key" string "$D3DM_FPS_VALUES"
    done
    rm -f "$BACKUP"
    ;;
  *)
    echo "用法：$0 check|apply|restore" >&2
    exit 64
    ;;
esac
