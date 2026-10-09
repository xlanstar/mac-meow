#!/bin/bash
# 發佈流程（開發端）。完整說明見 docs/development.md「發佈」。
#
# 用法：bash tools/release.sh <指令> <X.Y.Z>
#   check    只做發佈前檢查（乾淨工作目錄、在 main、Unreleased 有內容、版本號遞增、
#            tag 不存在、bash -n、patches/bin/SHA256SUMS、簽章與公證設定）
#   prepare  check 後改寫 CHANGELOG.md 與 VERSION，commit「chore(release): X.Y.Z」並建立 annotated tag vX.Y.Z（不 push）
#   publish  push main 與 tag；GitHub Actions（.github/workflows/release.yml）接著執行 ci，正式發佈 Release
#   ci       CI 專用：確認 tag 在 origin/main 上、VERSION 與 CHANGELOG 一致，再執行 build、draft 與 release
#   build    從 tag vX.Y.Z 以 git archive 取出乾淨原始碼到 build/release/，執行 app/build-app.sh，
#            產物放到 dist/release/X.Y.Z/：MacMeow-X.Y.Z.dmg、.sha256、release-notes.md
#            需設定 MACMEOW_SIGN_ID 與 MACMEOW_NOTARY_PROFILE（環境變數或 .env；Developer ID 簽章＋公證）；
#            MACMEOW_ALLOW_ADHOC=1 可改發未公證的 ad-hoc 版本
#   draft    以 dist/release/X.Y.Z/ 的產物建立或更新 GitHub Release 草稿（需 gh 登入或 GH_TOKEN）
#   release  下載草稿附件驗證 SHA-256、簽章、公證與版本後，正式發佈並標為 Latest（repo 首頁可見）
#
# CI 會直接正式發佈，所以 publish 之前必須以本機 build 的產物手動冒煙測試（見 docs/development.md）。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib.sh
source "$ROOT/tools/lib.sh"
load_env   # MACMEOW_SIGN_ID／MACMEOW_NOTARY_PROFILE（.env）；build 從 tag 建置時以環境變數傳給 build-app.sh
cd "$ROOT"

die() { echo "錯誤：$*" >&2; exit 1; }
ok()  { echo "  ✓ $*"; }

ver_valid() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
# ver_gt a b：a > b
ver_gt() {
  local IFS=. a b i
  read -r -a a <<<"$1"; read -r -a b <<<"$2"
  for i in 0 1 2; do
    (( a[i] > b[i] )) && return 0
    (( a[i] < b[i] )) && return 1
  done
  return 1
}

# changelog_section <標題>：輸出 CHANGELOG.md 中該 `## ` 標題下的內容（不含標題）
changelog_section() {
  awk -v h="## $1" 'f && /^## /{exit} f{print} index($0, h)==1 && (length($0)==length(h) || substr($0, length(h)+1, 1)==" "){f=1}' CHANGELOG.md
}

# 發佈版本預設必須 Developer ID 簽章並公證（見 docs/development.md「簽章與公證」）
adhoc_release() { [[ "${MACMEOW_ALLOW_ADHOC:-}" == 1 ]]; }
signing_check() {
  if adhoc_release; then
    echo "  ! MACMEOW_ALLOW_ADHOC=1：產物只有 ad-hoc 簽章，下載的使用者會被 Gatekeeper 擋下"
    return
  fi
  [[ -n "${MACMEOW_SIGN_ID:-}" && -n "${MACMEOW_NOTARY_PROFILE:-}" ]] \
    || die "需設定 MACMEOW_SIGN_ID 與 MACMEOW_NOTARY_PROFILE（或 MACMEOW_ALLOW_ADHOC=1 發佈未公證版本）"
  security find-identity -v -p codesigning | grep -F "$MACMEOW_SIGN_ID" | grep 'Developer ID Application' >/dev/null \
    || die "鑰匙圈找不到有效的 Developer ID Application 憑證：${MACMEOW_SIGN_ID}"
  ok "簽章憑證 ${MACMEOW_SIGN_ID}"
  local auth=(--keychain-profile "$MACMEOW_NOTARY_PROFILE")
  [[ -z "${MACMEOW_NOTARY_KEYCHAIN:-}" ]] || auth+=(--keychain "$MACMEOW_NOTARY_KEYCHAIN")
  xcrun notarytool history "${auth[@]}" >/dev/null 2>&1 \
    || die "notarytool profile「${MACMEOW_NOTARY_PROFILE}」無法登入（xcrun notarytool store-credentials）"
  ok "公證 profile ${MACMEOW_NOTARY_PROFILE}"
}

cmd_check() {
  local v="$1" cur branch n
  echo "發佈前檢查 ${v}："
  cur="$(cat VERSION)"
  ver_gt "$v" "$cur" || die "新版本 ${v} 必須大於目前的 VERSION ${cur}"
  ok "版本 ${cur} → ${v}"

  branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
  [[ "$branch" == "main" ]] || die "請在 main 分支發佈（目前：${branch:-detached}）"
  [[ -z "$(git status --porcelain)" ]] || die "工作目錄有未提交的變更"
  ok "main、工作目錄乾淨"

  git rev-parse -q --verify "refs/tags/v$v" >/dev/null && die "tag v${v} 已存在"
  ok "tag v${v} 尚未存在"

  n="$(changelog_section Unreleased | grep -c '^- ' || true)"
  (( n > 0 )) || die "CHANGELOG.md 的 ## Unreleased 沒有任何項目"
  ok "Unreleased 有 ${n} 項"

  local f bad=0
  while IFS= read -r f; do bash -n "$f" || bad=1; done < <(git ls-files '*.sh')
  (( bad == 0 )) || die "bash -n 失敗"
  ok "bash -n（$(git ls-files '*.sh' | wc -l | tr -d ' ') 個腳本）"
  if command -v shellcheck >/dev/null; then
    git ls-files 'scripts/*.sh' 'app/*.sh' | xargs shellcheck -x -S warning || die "shellcheck 有警告"
    ok "shellcheck（scripts/、app/）"
  fi
  swiftc -typecheck -swift-version 5 -parse-as-library -target arm64-apple-macos13.0 \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" app/Sources/*.swift || die "app/Sources 無法編譯"
  ok "swiftc -typecheck（app/Sources）"

  ( cd patches/bin/x86_64-windows && shasum -a 256 -c ../SHA256SUMS >/dev/null ) || die "patches/bin/SHA256SUMS 與 DLL 不符"
  ok "patches/bin/SHA256SUMS"

  signing_check
}

cmd_prepare() {
  local v="$1" today tmp
  cmd_check "$v"
  today="$(date +%F)"
  tmp="$(mktemp)"
  awk -v v="$v" -v d="$today" '
    !done && $0=="## Unreleased" { print; print ""; print "## " v " — " d; done=1; next }
    { print }' CHANGELOG.md >"$tmp"
  mv "$tmp" CHANGELOG.md
  printf '%s\n' "$v" >VERSION
  git add CHANGELOG.md VERSION
  git commit -q -m "chore(release): $v" -m "Move the Unreleased changelog entries under $v and set VERSION to $v."
  git tag -a "v$v" -m "MacMeow $v"
  echo "已建立 commit「chore(release): ${v}」與 tag v${v}（尚未 push）。"
  echo "下一步：bash tools/release.sh build ${v} 並冒煙測試，再 publish ${v}（push 後由 GitHub Actions 建置並正式發佈）"
}

# verify_dmg <dmg> <X.Y.Z>：dmg（非 ad-hoc 時）已簽章、公證；掛載後 App 簽章有效、已公證且 Gatekeeper 認可、版本正確
verify_dmg() {
  local dmg="$1" v="$2" chk mnt
  if ! adhoc_release; then
    codesign --verify "$dmg" || die "dmg 簽章驗證失敗"
    xcrun stapler validate -q "$dmg" || die "dmg 沒有公證票證"
    spctl --assess --type open --context context:primary-signature -vv "$dmg" 2>&1 \
      | grep 'source=Notarized Developer ID' >/dev/null \
      || die "Gatekeeper 未認可 dmg（spctl --assess --type open --context context:primary-signature -vv）"
    ok "dmg：Notarized Developer ID"
  fi
  chk="$(mktemp -d)"; mnt="$chk/mnt"
  hdiutil attach -nobrowse -readonly -noautoopen -quiet -mountpoint "$mnt" "$dmg" || die "無法掛載 ${dmg}"
  ditto "$mnt/MacMeow.app" "$chk/MacMeow.app"
  [[ -L "$mnt/應用程式" && -f "$mnt/.DS_Store" && -f "$mnt/.background/background.tiff" ]] \
    || { hdiutil detach -quiet "$mnt"; die "dmg 內缺少「應用程式」捷徑或視窗版面（.DS_Store、背景圖）"; }
  hdiutil detach -quiet "$mnt" || die "無法卸載 ${mnt}"
  codesign --verify --deep --strict "$chk/MacMeow.app" || die "dmg 內 App 簽章驗證失敗"
  ok "codesign"
  if ! adhoc_release; then
    xcrun stapler validate -q "$chk/MacMeow.app" || die "dmg 內 App 沒有公證票證"
    spctl --assess --type exec -vv "$chk/MacMeow.app" 2>&1 | grep 'source=Notarized Developer ID' >/dev/null \
      || die "Gatekeeper 未認可 dmg 內 App（spctl --assess --type exec -vv）"
    ok "App：Notarized Developer ID"
  fi
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$chk/MacMeow.app/Contents/Info.plist")" == "$v" ]] \
    || die "dmg 內 App 版本不是 ${v}"
  ok "App 版本 ${v}"
  rm -rf "$chk"
}

cmd_build() {
  local v="$1" src out dmg
  git rev-parse -q --verify "refs/tags/v$v" >/dev/null || die "找不到 tag v${v}，請先執行 prepare"
  src="$ROOT/build/release/$v"
  out="$ROOT/dist/release/$v"
  rm -rf "$src" "$out"; mkdir -p "$src" "$out"

  # 只用 tag 內已提交的檔案建置，避免工作目錄的未追蹤檔混入
  git archive "v$v" | tar -x -C "$src"
  [[ "$(cat "$src/VERSION")" == "$v" ]] || die "tag v${v} 的 VERSION 不是 ${v}"
  signing_check
  if adhoc_release; then
    MACMEOW_SIGN_ID='' MACMEOW_NOTARY_PROFILE='' bash "$src/app/build-app.sh"
  else
    bash "$src/app/build-app.sh"
  fi

  dmg="MacMeow-$v.dmg"
  cp "$src/dist/$dmg" "$out/"
  ( cd "$out" && shasum -a 256 "$dmg" >"$dmg.sha256" )

  verify_dmg "$out/$dmg" "$v"

  {
    changelog_section "$v" | awk 'NF{for(;b>0;b--)print ""; s=1; print; next} s{b++}'   # 去掉頭尾空行
    echo
    echo "## 安裝"
    echo
    if adhoc_release; then
      echo "下載 \`$dmg\`，開啟後把 \`MacMeow.app\` 拖到視窗右邊的「應用程式」資料夾。本版未經 Apple 公證：第一次開啟被擋時，到「系統設定 → 隱私權與安全性」按「仍要打開」。詳見 README。"
    else
      echo "下載 \`$dmg\`，開啟後把 \`MacMeow.app\` 拖到視窗右邊的「應用程式」資料夾，再從「應用程式」開啟。詳見 README。"
    fi
    echo
    echo "SHA-256：\`$(cut -d' ' -f1 "$out/$dmg.sha256")\`"
    echo
    echo "## 授權與原始碼（LGPL）"
    echo
    echo "App 內含以 LGPL-2.1-or-later 授權的修補版 Wine DLL，對應原始碼與修補如下："
    echo
    sed -n '/^| 項目/,/^$/p' "$src/patches/SOURCES.md"
  } >"$out/release-notes.md"

  echo "產物：$out"
  ls -1 "$out" | sed 's/^/  /'
  [[ -n "${GITHUB_ACTIONS:-}" ]] \
    || echo "請先冒煙測試 ${out}/${dmg}；正式發佈用 publish（由 CI 建置），CI 無法使用時改用 draft ${v} 與 release ${v}"
}

cmd_publish() {
  local v="$1"
  git rev-parse -q --verify "refs/tags/v$v" >/dev/null || die "找不到 tag v${v}，請先執行 prepare"
  git remote get-url origin >/dev/null 2>&1 || die "尚未設定 git remote origin"
  [[ "$(git rev-parse "v$v^{commit}")" == "$(git rev-parse main)" ]] || echo "注意：tag v${v} 不是 main 的最新 commit"
  git push --atomic origin main "v$v"   # 兩者同時成功或同時失敗
  echo "已 push。GitHub Actions 會建置、簽章、公證並正式發佈 Release（gh run watch 或 repo 的 Actions 頁面）。"
}

cmd_ci() {
  local v="$1"
  echo "CI 發佈 ${v}："
  git rev-parse -q --verify "refs/tags/v$v" >/dev/null || die "找不到 tag v${v}"
  [[ "$(git show "v$v:VERSION")" == "$v" ]] || die "tag v${v} 的 VERSION 不是 ${v}"
  git show "v$v:CHANGELOG.md" | grep "^## $v " >/dev/null || die "tag v${v} 的 CHANGELOG.md 沒有 ## ${v} 段落"
  ok "VERSION 與 CHANGELOG"
  git fetch -q origin main
  git merge-base --is-ancestor "v$v^{commit}" FETCH_HEAD || die "tag v${v} 不在 origin/main 上"
  ok "tag v${v} 在 origin/main 上"
  cmd_build "$v"
  cmd_draft "$v"
  cmd_release "$v"
}

cmd_draft() {
  local v="$1" out="$ROOT/dist/release/$1" state
  local assets=("$out/MacMeow-$v.dmg" "$out/MacMeow-$v.dmg.sha256")
  [[ -f "${assets[0]}" && -f "${assets[1]}" && -f "$out/release-notes.md" ]] || die "找不到 ${out} 的產物，請先執行 build"
  command -v gh >/dev/null || die "需要 gh（brew install gh）"
  if state="$(gh release view "v$v" --json isDraft --jq .isDraft 2>/dev/null)"; then
    [[ "$state" == true ]] || die "v${v} 已正式發佈，不覆蓋；請改發下一個 patch 版本"
    gh release upload "v$v" --clobber "${assets[@]}"
    gh release edit "v$v" --title "MacMeow $v" --notes-file "$out/release-notes.md"
    echo "已更新 GitHub Release 草稿 v${v}"
  else
    gh release create "v$v" --draft --verify-tag --title "MacMeow $v" \
      --notes-file "$out/release-notes.md" "${assets[@]}"
    echo "已建立 GitHub Release 草稿 v${v}"
  fi
  [[ -n "${GITHUB_ACTIONS:-}" ]] || echo "冒煙測試通過後：bash tools/release.sh release ${v}"
}

cmd_release() {
  local v="$1" dmg="MacMeow-$1.dmg" state tmp
  command -v gh >/dev/null || die "需要 gh（brew install gh）"
  echo "正式發佈 ${v}："
  state="$(gh release view "v$v" --json isDraft --jq .isDraft 2>/dev/null)" \
    || die "GitHub 上沒有 v${v} 的 Release，請先 publish（CI 建立草稿）或 draft"
  if [[ "$state" != true ]]; then
    echo "v${v} 已正式發佈：$(gh release view "v$v" --json url --jq .url)"
    return
  fi
  ok "草稿 v${v} 存在"

  # 驗證的是使用者實際會下載的附件，而非本機 dist/
  tmp="$(mktemp -d)"
  gh release download "v$v" --pattern "$dmg" --pattern "$dmg.sha256" -D "$tmp"
  ( cd "$tmp" && shasum -a 256 -c "$dmg.sha256" >/dev/null ) || die "${dmg} 與 ${dmg}.sha256 不符"
  ok "SHA-256"
  verify_dmg "$tmp/$dmg" "$v"
  rm -rf "$tmp"

  gh release edit "v$v" --draft=false --latest >/dev/null
  echo "已正式發佈 v${v}（Latest）：$(gh release view "v$v" --json url --jq .url)"
}

usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; }

(( $# == 2 )) || { usage; exit 2; }
ver_valid "$2" || die "版本格式需為 X.Y.Z：$2"
case "$1" in
  check)   cmd_check "$2" ;;
  prepare) cmd_prepare "$2" ;;
  build)   cmd_build "$2" ;;
  publish) cmd_publish "$2" ;;
  ci)      cmd_ci "$2" ;;
  draft)   cmd_draft "$2" ;;
  release) cmd_release "$2" ;;
  *) die "未知指令：$1" ;;
esac
