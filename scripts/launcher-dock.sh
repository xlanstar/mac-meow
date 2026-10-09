#!/bin/bash
# 登入器（貓貓TMS登入器.exe）是否顯示在 Dock（docs/technical-notes.md #10）。
# 在 Cyder shared bottle 的登錄寫入 AppDefaults\貓貓TMS登入器.exe\Mac Driver\CaptureDisplaysForFullscreen=y；
# 搭配 patch-cyder-winemac.sh 的修補，登入器會成為沒有 Dock 圖示的輔助程式。engine 未修補時這個值只影響
# 登入器全螢幕時是否鎖定螢幕（登入器不會全螢幕），沒有其他作用。
#
# 用法：bash scripts/launcher-dock.sh status|hide|show
#   status  已設定隱藏則回傳 0（讀 user.reg，不啟動 Wine）
#   hide    寫入設定（以 Wine 的 reg.exe；登入器下次啟動時生效）
#   show    刪除設定（uninstall.sh 會呼叫）
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

KEY="HKCU\\Software\\Wine\\AppDefaults\\${LAUNCHER_EXE}\\Mac Driver"
VALUE=CaptureDisplaysForFullscreen
# user.reg 中的 key 名稱：非 ASCII 字元存成 \x 跳脫（wineserver dump_strW），對應 LAUNCHER_EXE。
REG_SECTION='[Software\\Wine\\AppDefaults\\\x8c93\x8c93TMS\x767b\x5165\x5668.exe\\Mac Driver]'
REG_LINE="\"$VALUE\"=\"y\""

hidden() {
  [[ -f "$CYDER_PREFIX/user.reg" ]] || return 1
  SECTION="$REG_SECTION" LINE="$REG_LINE" /usr/bin/awk '
    /^\[/ { in_key = (index($0, ENVIRON["SECTION"]) == 1); next }
    in_key && $0 == ENVIRON["LINE"] { found = 1 }
    END { exit !found }' "$CYDER_PREFIX/user.reg"
}

case "${1:-}" in
  status)
    if hidden; then
      echo "登入器 Dock 圖示：隱藏"
    else
      echo "登入器 Dock 圖示：顯示"
      exit 1
    fi
    ;;
  hide)
    hidden && {
      echo "登入器 Dock 圖示：已設定隱藏"
      exit 0
    }
    cyder_ready || die "Cyder prefix 尚未初始化，請先開啟一次 Cyder"
    run_wine_tool reg add "$KEY" /v "$VALUE" /t REG_SZ /d y /f || die "無法寫入 Wine 登錄（${KEY}）"
    echo "登入器 Dock 圖示：已設定隱藏"
    ;;
  show)
    hidden || {
      echo "登入器 Dock 圖示：未設定隱藏"
      exit 0
    }
    run_wine_tool reg delete "$KEY" /v "$VALUE" /f || die "無法刪除 Wine 登錄值（${KEY}）"
    echo "登入器 Dock 圖示：已恢復顯示"
    ;;
  *)
    echo "用法：$0 status|hide|show" >&2
    exit 64
    ;;
esac
