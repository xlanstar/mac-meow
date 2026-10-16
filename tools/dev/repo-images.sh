#!/bin/bash
# 產生 GitHub repo 用的圖片（2560×1280 JPEG）到 build/repo-images/：
#   social-preview.jpg       連結卡片（repo Settings → General → Social preview 上傳；不放進 repo）
#   readme-hero-light.jpg    README 頂部主圖（淺色模式）
#   readme-hero-dark.jpg     README 頂部主圖（深色模式）
#
# 用法：bash tools/dev/repo-images.sh [--update-readme]
#   --update-readme   另把 readme-hero-*.jpg 複製到 docs/images/（README 引用的版本）
#   App 只在選單列，圖中的選單由 tools/src/repo-images/menu.js 以 HTML 重現（不需截圖；選單改變時更新該檔），
#   版本號取自 VERSION。圖示取自 app/build-app.sh 產生的 build/app/AppIcon.iconset。需要 Google Chrome。
set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

UPDATE_README=0
case "${1:-}" in
  --update-readme) UPDATE_README=1 ;;
  "") ;;
  *) usage_doc ;;
esac
VERSION="$(cat "$ROOT/VERSION")"
APP_ICON="$ROOT/build/app/AppIcon.iconset/icon_256x256@2x.png"
TEMPLATES="$ROOT/tools/src/repo-images"
OUT="$ROOT/build/repo-images"
README_IMAGES="$ROOT/docs/images"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

[[ -f "$APP_ICON" ]] || die "找不到 App 圖示，先執行 bash app/build-app.sh"
[[ -x "$CHROME" ]] || die "需要 Google Chrome"

mkdir -p "$OUT"
cp "$TEMPLATES"/*.html "$TEMPLATES"/*.css "$TEMPLATES"/*.js "$OUT/"
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

render "social-preview.html?version=${VERSION}" social-preview
render "readme-hero.html?version=${VERSION}" readme-hero-light
render "readme-hero.html?theme=dark&version=${VERSION}" readme-hero-dark

if ((UPDATE_README)); then
  mkdir -p "$README_IMAGES"
  cp "$OUT/readme-hero-light.jpg" "$OUT/readme-hero-dark.jpg" "$README_IMAGES/"
  echo "已更新 $README_IMAGES/readme-hero-{light,dark}.jpg"
fi
