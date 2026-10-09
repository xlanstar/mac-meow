#!/bin/bash
# 產生 GitHub repo 用的圖片（2560×1280 JPEG）到 build/repo-images/：
#   social-preview.jpg       連結卡片（repo Settings → General → Social preview 上傳；不放進 repo）
#   readme-hero-light.jpg    README 頂部主圖（淺色模式）
#   readme-hero-dark.jpg     README 頂部主圖（深色模式）
#
# 用法：bash tools/repo-images.sh [--update-readme] [App 視窗截圖.png]
#   --update-readme   另把 readme-hero-*.jpg 複製到 docs/images/（README 引用的版本）
#   App 視窗截圖預設 debug/app-shot.png（含透明圓角：⌘⇧4 → 空白鍵 → 點 App 視窗）。
#   圖示取自 app/build-app.sh 產生的 build/app/AppIcon.iconset。需要 Google Chrome。
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

UPDATE_README=0
if [ "${1:-}" = "--update-readme" ]; then
  UPDATE_README=1
  shift
fi
APP_WINDOW_SHOT="${1:-$ROOT/debug/app-shot.png}"
APP_ICON="$ROOT/build/app/AppIcon.iconset/icon_256x256@2x.png"
TEMPLATES="$ROOT/tools/src/repo-images"
OUT="$ROOT/build/repo-images"
README_IMAGES="$ROOT/docs/images"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

[ -f "$APP_WINDOW_SHOT" ] || {
  echo "找不到 App 視窗截圖：$APP_WINDOW_SHOT" >&2
  exit 1
}
[ -f "$APP_ICON" ] || {
  echo "找不到 App 圖示，先執行 bash app/build-app.sh" >&2
  exit 1
}
[ -x "$CHROME" ] || {
  echo "需要 Google Chrome" >&2
  exit 1
}

mkdir -p "$OUT"
cp "$TEMPLATES"/*.html "$TEMPLATES"/*.css "$OUT/"
cp "$APP_WINDOW_SHOT" "$OUT/app-window.png"
cp "$APP_ICON" "$OUT/app-icon.png"

# render <頁面[?參數]> <輸出名稱>：以 1280×640、2 倍解析度截圖，再轉成 JPEG（GitHub 上限 1 MB）
render() {
  local png="$OUT/$2.png"
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1280,640 --screenshot="$png" "file://$OUT/$1" 2>/dev/null
  sips -s format jpeg -s formatOptions 88 "$png" --out "$OUT/$2.jpg" >/dev/null
  rm -f "$png"
  echo "$OUT/$2.jpg"
}

render social-preview.html social-preview
render readme-hero.html readme-hero-light
render "readme-hero.html?theme=dark" readme-hero-dark

if [ "$UPDATE_README" = 1 ]; then
  mkdir -p "$README_IMAGES"
  cp "$OUT/readme-hero-light.jpg" "$OUT/readme-hero-dark.jpg" "$README_IMAGES/"
  echo "已更新 $README_IMAGES/readme-hero-{light,dark}.jpg"
fi
