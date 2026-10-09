#!/bin/bash
# 擷取 Wine 遊戲視窗（被其他視窗遮住也可，螢幕鎖定時不行）：screencapture -l <CGWindowID>。
# 用法：bash tools/shot-game.sh [輸出檔=debug/shot-<時間>.png] [視窗標題=MapleStory]
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

out="${1:-$DEBUG_DIR/shot-$(date +%Y%m%d-%H%M%S).png}"
name="${2:-MapleStory}"
mkdir -p "$(dirname "$out")"

# 取標題相符的 wine 視窗中面積最大者；標題以 argv 傳入，避免字串拼接進 JavaScript。
id="$(/usr/bin/osascript -l JavaScript - "$name" <<'JS'
ObjC.import('CoreGraphics');
function run(argv) {
  var list = ObjC.deepUnwrap(ObjC.castRefToObject($.CGWindowListCopyWindowInfo(0, 0)));
  var best = 0, area = 0;
  list.forEach(function (w) {
    if (w.kCGWindowOwnerName === 'wine' && (w.kCGWindowName || '') === argv[0]) {
      var a = w.kCGWindowBounds.Width * w.kCGWindowBounds.Height;
      if (a > area) { area = a; best = w.kCGWindowNumber; }
    }
  });
  return best;
}
JS
)"
[[ -n "$id" && "$id" != 0 ]] || die "找不到視窗：${name}"
/usr/sbin/screencapture -x -o -l "$id" "$out"
echo "$out"
