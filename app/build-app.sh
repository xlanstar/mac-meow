#!/bin/bash
# 打包 MacMeow.app（以及可分享的 dmg）。用法：bash app/build-app.sh
# 需要 Xcode 或 Command Line Tools（swiftc、iconutil）；產物只用系統內建 framework。
# 產物：dist/MacMeow.app、dist/MacMeow-<版本>.dmg；中間檔在 build/app/。
#
# 簽章（見 docs/development.md「簽章與公證」）：
#   預設 ad-hoc 簽章，只適合自己用；下載的使用者會被 Gatekeeper 擋下。
#   MACMEOW_SIGN_ID=<Developer ID Application 憑證名稱或 SHA-1>：Developer ID 簽章（Hardened Runtime + 時間戳記）
#   MACMEOW_NOTARY_PROFILE=<notarytool keychain profile>：另外送 Apple 公證並把票證釘進 App 與 dmg（需搭配 MACMEOW_SIGN_ID）
#   MACMEOW_NOTARY_KEYCHAIN=<keychain 路徑>：profile 不在預設鑰匙圈時指定（CI 的暫時鑰匙圈）
#   可寫在 repo 根目錄的 .env（範本 .env.example）；環境變數優先。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../tools/lib.sh
source "$ROOT/tools/lib.sh"
load_env
VERSION="$(cat "$ROOT/VERSION")"
DIST="$ROOT/dist"; APP="$DIST/MacMeow.app"
RES="$APP/Contents/Resources"
WORK="$ROOT/build/app"
TARGET="arm64-apple-macos13.0"   # 與 Info.plist 的 LSMinimumSystemVersion 一致

command -v swiftc >/dev/null 2>&1 && xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 \
  || { echo "需要 Xcode 或 Command Line Tools：xcode-select --install" >&2; exit 1; }
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SIGN_ID="${MACMEOW_SIGN_ID:-}"
NOTARY_PROFILE="${MACMEOW_NOTARY_PROFILE:-}"
[[ -z "$NOTARY_PROFILE" || -n "$SIGN_ID" ]] \
  || { echo "MACMEOW_NOTARY_PROFILE 需要搭配 MACMEOW_SIGN_ID（Developer ID Application 憑證）" >&2; exit 1; }
NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
[[ -z "${MACMEOW_NOTARY_KEYCHAIN:-}" ]] || NOTARY_AUTH+=(--keychain "$MACMEOW_NOTARY_KEYCHAIN")

rm -rf "$APP" "$WORK"
mkdir -p "$APP/Contents/MacOS" "$RES/scripts/lib" "$RES/patches/bin" "$RES/zh-Hant.lproj" "$WORK"

# SwiftUI 主程式（app/Sources）
swiftc -O -swift-version 5 -parse-as-library -module-name MacMeow \
  -sdk "$SDK" -target "$TARGET" \
  -o "$APP/Contents/MacOS/MacMeow" "$ROOT"/app/Sources/*.swift

# App 圖示（app/make-icon.swift 繪製）
swiftc -O -sdk "$SDK" -o "$WORK/make-icon" "$ROOT/app/make-icon.swift"
"$WORK/make-icon" "$WORK/AppIcon.iconset"
iconutil -c icns -o "$RES/AppIcon.icns" "$WORK/AppIcon.iconset"

# 只打包使用者流程（scripts/ 下的腳本與共用函式）；uninstall.sh 需要 repo 內的 tools/，不打包。
for s in play.sh setup-loopback.sh patch-cyder-loopback.sh patch-cyder-dlls.sh; do
  install -m 755 "$ROOT/scripts/$s" "$RES/scripts/$s"
done
install -m 644 "$ROOT/scripts/lib/common.sh" "$RES/scripts/lib/common.sh"
cp -R "$ROOT/patches/bin/x86_64-windows" "$ROOT/patches/bin/SHA256SUMS" "$RES/patches/bin/"

cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MacMeow</string>
  <key>CFBundleIdentifier</key><string>tw.macmeow.launcher</string>
  <key>CFBundleName</key><string>MacMeow</string>
  <key>CFBundleDisplayName</key><string>貓貓谷 for Mac</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>zh-Hant</string>
  <key>CFBundleLocalizations</key><array><string>zh-Hant</string></array>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License（Wine 修補為 LGPL-2.1-or-later）</string>
</dict>
</plist>
PLIST

# App 內只有一個 Mach-O；腳本與 Windows DLL 是資源檔，由 bundle 簽章一併封存，不需要 --deep。
if [[ -n "$SIGN_ID" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"

# notarize <檔案>：送 Apple 公證並等待結果；失敗時印出查詢原因的指令並結束
notarize() {
  local result="$WORK/notary.plist" status id
  echo "送交 Apple 公證：$(basename "$1")（通常需要數分鐘）⋯"
  xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait --output-format plist >"$result" || true
  # notarytool 本身出錯（例如找不到 profile）時 plist 是空的；PlistBuddy 的錯誤訊息印在 stdout，只採用成功時的輸出
  status="$(/usr/libexec/PlistBuddy -c 'Print status' "$result" 2>/dev/null)" || status=""
  [[ "$status" == "Accepted" ]] && return
  id="$(/usr/libexec/PlistBuddy -c 'Print id' "$result" 2>/dev/null)" || id=""
  if [[ -n "$id" ]]; then
    echo "公證失敗（${status:-未知狀態}）。查看原因：xcrun notarytool log ${id} ${NOTARY_AUTH[*]}" >&2
  else
    echo "公證送交失敗，見上方 notarytool 訊息" >&2
  fi
  exit 1
}

# 先公證 App 並把票證釘進 App（離線也能通過 Gatekeeper），再放進 dmg；
# dmg 的雜湊與 App 不同，所以 dmg 另外簽章、公證並釘上票證。
if [[ -n "$NOTARY_PROFILE" ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$WORK/MacMeow-notarize.zip"
  notarize "$WORK/MacMeow-notarize.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

# dmg：App 加上「應用程式」捷徑，使用者開啟後直接拖曳安裝
DMG="$DIST/MacMeow-$VERSION.dmg"
STAGE="$WORK/dmg"
rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/MacMeow.app"
ln -s /Applications "$STAGE/Applications"
# hdiutil 偶爾回報 Resource busy（CI 常見），重試幾次
for i in 1 2 3; do
  hdiutil create -volname "MacMeow" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov -quiet "$DMG" && break
  (( i < 3 )) || { echo "hdiutil create 失敗" >&2; exit 1; }
  sleep 3
done
if [[ -n "$SIGN_ID" ]]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
  codesign --verify "$DMG"
fi
if [[ -n "$NOTARY_PROFILE" ]]; then
  notarize "$DMG"
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then sig="Developer ID＋公證"
elif [[ -n "$SIGN_ID" ]]; then sig="憑證簽章（未公證）"
else sig="ad-hoc（只適合自己用）"; fi
echo "完成：${APP}（簽章：${sig}）"
echo "      $DMG"
