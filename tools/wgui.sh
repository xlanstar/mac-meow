#!/bin/bash
# 在 Cyder shared bottle 內執行 wgui.exe（與遊戲同一個 wineserver）：列出視窗、點擊、按鍵、截圖。
# 預設經 Terminal.app 執行並等待結果（agent shell／SSH 直接跑 GUI 類 Wine 程式會卡住）；
# 已在 Terminal.app 內時可加 --here 直接執行。
#
# 用法：bash tools/wgui.sh [--here] list|click|sclick|shot|fg|key ...（參數見 tools/src/wgui/wgui.c）
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

need_tool wgui.exe
if [[ "${1:-}" == --here ]]; then
  shift
  run_wine "$TOOLS_BIN/wgui.exe" "$@"
else
  in_terminal 60 bash "$ROOT/tools/wgui.sh" --here "$@"
fi
