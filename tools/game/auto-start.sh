#!/bin/bash
# 等待登入器視窗出現，在「開始遊戲」按鈕位置送出真實點擊（wgui sclick → SendInput），直到 MapleStory.exe 啟動。
# 用法：bash tools/game/auto-start.sh [--here]（遊戲需已由 play.sh 或 run-game.sh 啟動到登入器畫面）
#   預設整個腳本經 Terminal.app 執行一次並等待結果（agent shell／SSH 直接跑 GUI 類 Wine 程式會卡住）；
#   已在 Terminal.app 內時可加 --here 直接執行。
set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

# 「開始遊戲」按鈕相對於登入器視窗左上角的位置
BUTTON_X=287 BUTTON_Y=455
LOGIN_WINDOW="" # wgui list 中登入器視窗那一行

wgui() { bash "$ROOT/tools/diag/wgui.sh" --here "$@"; }

find_login_window() {
  LOGIN_WINDOW="$(wgui list 2>/dev/null | grep 'vis=1.*LoginTms' | head -1 || true)"
  [[ -n "$LOGIN_WINDOW" ]]
}
maple_started() { [[ -n "$(maple_pids)" ]]; }

click_start() {
  local left top _
  wait_until 180 find_login_window || die "登入器視窗未出現"
  # wgui list 的格式：... rect=(left,top)-(right,bottom) ...
  read -r left top <<<"$(sed -E 's/.*rect=\((-?[0-9]+),(-?[0-9]+)\).*/\1 \2/' <<<"$LOGIN_WINDOW")"
  sleep 3 # 等登入器畫面繪製完成
  for _ in 1 2 3; do
    wgui sclick $((left + BUTTON_X)) $((top + BUTTON_Y)) >/dev/null
    if wait_until 30 maple_started; then
      echo "MapleStory 已啟動"
      return 0
    fi
  done
  die "點擊後 MapleStory 未啟動"
}

case "${1:-}" in
  --here) click_start ;;
  "")
    need_tool wgui.exe # 在進入 Terminal 前建置，避免建置時間計入逾時
    # 等待視窗 180 秒 + 3 次點擊各等 30 秒，再加餘裕
    in_terminal 330 bash "$ROOT/tools/game/auto-start.sh" --here
    ;;
  *) usage "[--here]" ;;
esac
