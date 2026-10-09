#!/bin/bash
# 替 Cyder engine 的 wine 執行檔換上「可除錯」簽章（ad-hoc + get-task-allow，移除 hardened runtime），
# 讓 tools/stack.sh（machstack、LLDB）可以讀取 Rosetta 下的遊戲程序。僅供開發診斷；查完請 restore。
# 原檔備份為 *.macmeow-orig；是否為除錯簽章以 entitlements 是否含 get-task-allow 判斷。
# scripts/uninstall.sh 會呼叫 restore，因此本腳本只用 macOS 內建指令。
#
# 用法：bash tools/sign-debug.sh status|apply|restore
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

FILES=("$CYDER_ENGINE/bin/wine" "$CYDER_ENGINE/lib/wine/x86_64-unix/wine")

entitlements() { /usr/bin/codesign -d --entitlements :- "$1" 2>/dev/null; }
debug_signed() { [[ "$(entitlements "$1")" == *com.apple.security.get-task-allow* ]]; }
engine_path() { echo "${1#"$CYDER_ENGINE"/}"; }

cmd_status() {
  local f
  for f in "${FILES[@]}"; do
    printf '%s：' "$(engine_path "$f")"
    if debug_signed "$f"; then printf '除錯簽章 '; else printf '原廠簽章 '; fi
    /usr/bin/codesign -dv "$f" 2>&1 | /usr/bin/grep -o 'flags=[^ ]*' || echo
  done
}

# debug_entitlements <輸出檔>：原有 entitlements 再加上 get-task-allow。
debug_entitlements() {
  entitlements "${FILES[1]}" >"$1" || true
  [[ -s "$1" ]] || /usr/bin/plutil -create xml1 "$1"
  /usr/libexec/PlistBuddy -c 'Add :com.apple.security.get-task-allow bool true' "$1" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c 'Set :com.apple.security.get-task-allow true' "$1"
}

cmd_apply() {
  local f ent
  require_wine_stopped "重新簽章 wine"
  ent="$(mktemp)"
  trap 'rm -f "$ent"' EXIT
  debug_entitlements "$ent"
  for f in "${FILES[@]}"; do
    [[ -f "$f" ]] || die "找不到 ${f}"
    debug_signed "$f" && continue
    cp -p "$f" "$f.macmeow-orig"
    /usr/bin/codesign -f -s - --entitlements "$ent" "$f"
  done
  echo "已套用除錯簽章（原檔 *.macmeow-orig）"
}

cmd_restore() {
  local f restored=0
  for f in "${FILES[@]}"; do
    [[ -f "$f.macmeow-orig" ]] || continue
    require_wine_stopped "還原 wine 簽章"
    if debug_signed "$f"; then
      cp -p "$f.macmeow-orig" "$f"
    else
      echo "$(engine_path "$f")：目前不是除錯簽章版（engine 已更新？），只刪除過期備份"
    fi
    rm -f "$f.macmeow-orig"
    restored=1
  done
  if ((restored)); then echo "已還原原廠簽章"; else echo "除錯簽章：無備份"; fi
}

case "${1:-}" in
  status | apply | restore) "cmd_$1" ;;
  *) usage "status|apply|restore" ;;
esac
