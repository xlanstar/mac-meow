#!/bin/bash
# 替 Cyder engine 的 wine 執行檔換上「可除錯」簽章（ad-hoc + get-task-allow，移除 hardened runtime），
# 讓 tools/stack.sh（machstack、LLDB）可以讀取 Rosetta 下的遊戲程序。僅供開發診斷；查完請 restore。
# 原檔備份為 *.macmeow-orig。status、restore 與檔案清單在 scripts/lib/common.sh（uninstall.sh 也會還原）。
#
# 用法：bash tools/sign-debug.sh status|apply|restore
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# debug_entitlements <輸出檔>：原有 entitlements 再加上 get-task-allow。
debug_entitlements() {
  wine_entitlements "${DEBUG_SIGN_FILES[1]}" >"$1" || true
  [[ -s "$1" ]] || /usr/bin/plutil -create xml1 "$1"
  /usr/libexec/PlistBuddy -c 'Add :com.apple.security.get-task-allow bool true' "$1" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c 'Set :com.apple.security.get-task-allow true' "$1"
}

cmd_apply() {
  local f
  require_wine_stopped "重新簽章 wine"
  ENT="$(mktemp)" # 全域：EXIT trap 執行時 local 已失效
  trap 'rm -f "$ENT"' EXIT
  debug_entitlements "$ENT"
  for f in "${DEBUG_SIGN_FILES[@]}"; do
    [[ -f "$f" ]] || die "找不到 ${f}"
    debug_signed "$f" && continue
    cp -p "$f" "$f.macmeow-orig"
    /usr/bin/codesign -f -s - --entitlements "$ENT" "$f"
  done
  echo "已套用除錯簽章（原檔 *.macmeow-orig）"
}

case "${1:-}" in
  status) debug_sign_status ;;
  apply) cmd_apply ;;
  restore) debug_sign_restore ;;
  *) usage "status|apply|restore" ;;
esac
