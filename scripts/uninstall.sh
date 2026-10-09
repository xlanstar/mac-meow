#!/bin/bash
# 移除本專案對系統與 Cyder 所做的所有變更（不刪除遊戲、Cyder 或其設定）：
#   1. 還原 Cyder engine：wineserver（loopback 修補）、wsock32.dll／advapi32.dll、winemac.so（Dock 圖示）、
#      開發用除錯簽章；刪除 shared bottle 登錄中登入器的 Dock 圖示設定
#   2. 移除 lo0 位址與 LaunchDaemon（需要管理員密碼）
#   3. 刪除 MacMeow.app 的設定與記錄
# 用法：bash scripts/uninstall.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

require_wine_stopped "執行移除"

rc=0
bash "$ROOT/scripts/launcher-dock.sh" show || rc=1
bash "$ROOT/scripts/patch-cyder-loopback.sh" restore || rc=1
bash "$ROOT/scripts/patch-cyder-dlls.sh" restore || rc=1
bash "$ROOT/scripts/patch-cyder-winemac.sh" restore || rc=1
bash "$ROOT/tools/sign-debug.sh" restore || rc=1

echo "移除 lo0 位址與 LaunchDaemon（需要管理員密碼）："
sudo bash "$ROOT/scripts/setup-loopback.sh" uninstall || rc=1

rm -rf "$MACMEOW_SUPPORT" "$MACMEOW_LOGS" "$MACMEOW_CACHE" \
  "$HOME/Library/Saved Application State/$MACMEOW_BUNDLE_ID.savedState"
# SwiftUI 視窗位置與檢查更新設定（tw.macmeow.launcher 偏好設定）
/usr/bin/defaults delete "$MACMEOW_BUNDLE_ID" >/dev/null 2>&1 || true
echo "已刪除 MacMeow.app 的設定與記錄"

if ((rc)); then
  echo "部分步驟失敗，請檢查上方訊息後重新執行。" >&2
else
  echo "完成。Cyder 的全域設定（wineLocale、graphicsBackend、msync、esync）保留；如需還原請在 Cyder 設定中調整。"
fi
exit $rc
