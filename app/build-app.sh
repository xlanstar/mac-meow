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
DIST="$ROOT/dist"
APP="$DIST/MacMeow.app"
RES="$APP/Contents/Resources"
WORK="$ROOT/build/app"
TARGET="arm64-apple-macos13.0" # 與 Info.plist 的 LSMinimumSystemVersion 一致

command -v swiftc >/dev/null 2>&1 && xcrun --sdk macosx --show-sdk-path >/dev/null 2>&1 \
  || {
    echo "需要 Xcode 或 Command Line Tools：xcode-select --install" >&2
    exit 1
  }
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SIGN_ID="${MACMEOW_SIGN_ID:-}"
NOTARY_PROFILE="${MACMEOW_NOTARY_PROFILE:-}"
[[ -z "$NOTARY_PROFILE" || -n "$SIGN_ID" ]] \
  || {
    echo "MACMEOW_NOTARY_PROFILE 需要搭配 MACMEOW_SIGN_ID（Developer ID Application 憑證）" >&2
    exit 1
  }
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
for s in play.sh report.sh setup-loopback.sh patch-cyder-loopback.sh patch-cyder-dlls.sh patch-cyder-winemac.sh \
  launcher-dock.sh session.sh update.sh; do
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
  <key>CFBundleIdentifier</key><string>$MACMEOW_BUNDLE_ID</string>
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
  # staple 釘完會自行驗證（失敗回傳非 0），不必再跑 stapler validate
  xcrun stapler staple -q "$APP"
fi

# retry <次數> <指令...>：hdiutil／diskutil 偶爾回報 Resource busy（CI 常見），失敗時稍候重試
retry() {
  local n="$1" i
  shift
  for ((i = 1; ; i++)); do
    "$@" && return
    ((i < n)) || {
      echo "失敗（已試 ${n} 次）：$*" >&2
      return 1
    }
    sleep 3
  done
}

# layout_dmg <掛載點>：請 Finder 設定 dmg 視窗（背景、圖示位置、隱藏工具列），結果存在 .DS_Store。
# 版面座標與 app/make-dmg-background.swift 一致。Finder 沒回應（例如等待「自動化」權限）時 90 秒後放棄。
layout_dmg() {
  local mnt="$1" pid watchdog rc=0
  /usr/bin/osascript - "$VOLNAME" "$LINK" <<'OSA' &
on run argv
  set volName to item 1 of argv
  set linkName to item 2 of argv
  tell application "Finder"
    tell disk volName
      open
      set cw to container window
      set current view of cw to icon view
      set toolbar visible of cw to false
      set statusbar visible of cw to false
      set pathbar visible of cw to false
      set bounds of cw to {200, 120, 840, 552}
      set opts to icon view options of cw
      set arrangement of opts to not arranged
      set icon size of opts to 128
      set text size of opts to 13
      set label position of opts to bottom
      set shows item info of opts to false
      set shows icon preview of opts to false
      set background picture of opts to file ".background:background.tiff"
      set position of item "MacMeow.app" of cw to {170, 205}
      set position of item linkName of cw to {470, 205}
      -- 有開「顯示隱藏檔」的使用者也看得到點檔；移到視窗外，免得擠亂版面
      repeat with f in {".background", ".VolumeIcon.icns", ".fseventsd", ".Trashes", ".DS_Store"}
        try
          set position of item f of cw to {900, 600}
        end try
      end repeat
      close
      open
      update without registering applications
      delay 1
      close
    end tell
  end tell
end run
OSA
  pid=$!
  (
    sleep 90
    kill "$pid" 2>/dev/null
  ) &
  watchdog=$!
  wait "$pid" || rc=$?
  # 收掉看門狗；wait 吃掉 bash 的「Terminated: 15」工作通知
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  ((rc == 0)) || return 1
  # Finder 非同步寫入 .DS_Store
  for _ in $(seq 20); do
    [[ -f "$mnt/.DS_Store" ]] && return
    sleep 0.5
  done
  return 1
}

# dmg：App、「應用程式」捷徑、背景圖與磁碟圖示；先做可寫入映像讓 Finder 排版，再壓縮成唯讀 dmg
DMG="$DIST/MacMeow-$VERSION.dmg"
VOLNAME="貓貓谷 for Mac"
LINK="應用程式"
STAGE="$WORK/dmg"
# 同名磁碟已掛載時 Finder 無法分辨要排版哪一個
[[ ! -e "/Volumes/$VOLNAME" ]] || {
  echo "請先退出已掛載的「${VOLNAME}」磁碟" >&2
  exit 1
}
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/MacMeow.app"
ln -s /Applications "$STAGE/$LINK"
swiftc -O -sdk "$SDK" -o "$WORK/make-dmg-background" "$ROOT/app/make-dmg-background.swift"
"$WORK/make-dmg-background" "$WORK/dmg-bg"
tiffutil -cathidpicheck "$WORK/dmg-bg/background.png" "$WORK/dmg-bg/background@2x.png" \
  -out "$STAGE/.background/background.tiff" 2>/dev/null

RW="$WORK/MacMeow-rw.dmg"
retry 3 hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW \
  -size "$(($(du -sm "$STAGE" | cut -f1) + 20))m" -ov -quiet "$RW"
# 不指定 -mountpoint（/Volumes 只有 root 可寫），由系統掛載後讀回路徑
MNT="$(retry 3 dmg_attach "$RW" | awk -F'\t' '$NF ~ /^\/Volumes\// {print $NF}')"
[[ "$MNT" == "/Volumes/$VOLNAME" ]] || {
  echo "dmg 掛載位置不符：${MNT:-（無）}" >&2
  exit 1
}
# 磁碟圖示：-srcfolder 不會複製 .VolumeIcon.icns，所以掛載後才放；根目錄 FinderInfo 設 kHasCustomIcon（0x0400）。
# 排版前先放，Finder 才能把它移到視窗外（開了「顯示隱藏檔」也不會出現在安裝畫面）
set_volume_icon() {
  [[ -f "$MNT/.VolumeIcon.icns" ]] || cp "$RES/AppIcon.icns" "$MNT/.VolumeIcon.icns"
  chflags hidden "$MNT/.VolumeIcon.icns"
  xattr -wx com.apple.FinderInfo "0000000000000000040000000000000000000000000000000000000000000000" "$MNT"
}
set_volume_icon
if ! layout_dmg "$MNT"; then
  echo "警告：Finder 無法設定 dmg 視窗版面（需允許終端機控制 Finder：系統設定 → 隱私權與安全性 → 自動化），改用預設版面" >&2
fi
# Finder 的 update 會刪掉圖示並清掉 FinderInfo，但 .DS_Store 裡的位置會保留；排版後補回
set_volume_icon
rm -rf "$MNT/.fseventsd" "$MNT/.Trashes"
sync
retry 3 hdiutil detach "$MNT" -quiet
retry 3 hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -ov -quiet -o "$DMG"
rm -f "$RW"
if [[ -n "$SIGN_ID" ]]; then
  codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
  codesign --verify "$DMG"
fi
if [[ -n "$NOTARY_PROFILE" ]]; then
  notarize "$DMG"
  xcrun stapler staple -q "$DMG"
fi

if [[ -n "$NOTARY_PROFILE" ]]; then
  sig="Developer ID＋公證"
elif [[ -n "$SIGN_ID" ]]; then
  sig="憑證簽章（未公證）"
else sig="ad-hoc（只適合自己用）"; fi
echo "完成：${APP}（簽章：${sig}）"
echo "      $DMG"
