#!/bin/bash
# 等待登入器視窗出現，在「開始遊戲」按鈕位置送出真實點擊（wgui sclick → SendInput），直到 MapleStory.exe 啟動。
# 用法：bash tools/auto-start.sh（遊戲需已由 play.sh 或 run-game.sh 啟動到登入器畫面）
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

# 「開始遊戲」按鈕相對於登入器視窗左上角的位置
BUTTON_X=287 BUTTON_Y=455

find_login_window() {
  line="$(bash "$ROOT/tools/wgui.sh" list 2>/dev/null | grep 'vis=1.*LoginTms' | head -1 || true)"
  [[ -n "$line" ]]
}
maple_started() { [[ -n "$(maple_pids)" ]]; }

line=""
wait_until 180 find_login_window || die "登入器視窗未出現"
# wgui list 的格式：... rect=(left,top)-(right,bottom) ...
read -r left top <<<"$(sed -E 's/.*rect=\((-?[0-9]+),(-?[0-9]+)\).*/\1 \2/' <<<"$line")"
sleep 3   # 等登入器畫面繪製完成

for _ in 1 2 3; do
  bash "$ROOT/tools/wgui.sh" sclick $((left + BUTTON_X)) $((top + BUTTON_Y)) >/dev/null
  if wait_until 30 maple_started; then echo "MapleStory 已啟動"; exit 0; fi
done
die "點擊後 MapleStory 未啟動"
