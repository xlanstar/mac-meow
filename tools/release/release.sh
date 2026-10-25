#!/bin/bash
# 發佈流程（開發端）。完整說明見 docs/release.md。
#
# 用法：bash tools/release/release.sh <指令> <X.Y.Z>
#   check    只做發佈前檢查（乾淨工作目錄、在 main、Unreleased 有內容、版本號遞增、
#            tag 不存在、bash -n、App 編譯與 Core 單元測試、patches/bin/SHA256SUMS、Homebrew cask 範本、簽章與公證設定）
#   prepare  check 後改寫 CHANGELOG.md 與 VERSION，commit「chore(release): X.Y.Z」並建立 annotated tag vX.Y.Z（不 push）
#   publish  push main 與 tag；GitHub Actions（.github/workflows/release.yml）接著執行 ci，正式發佈 Release
#   ci       CI 專用：確認 tag 在 origin/main 上、VERSION 與 CHANGELOG 一致，再執行 build、draft、release 與 tap
#   build    從 tag vX.Y.Z 以 git archive 取出乾淨原始碼到 build/release/，執行 app/build-app.sh，
#            產物放到 dist/release/X.Y.Z/：MacMeow-X.Y.Z.dmg、.sha256、release-notes.md
#            需設定 MACMEOW_SIGN_ID 與 MACMEOW_NOTARY_PROFILE（環境變數或 .env；Developer ID 簽章＋公證）；
#            MACMEOW_ALLOW_ADHOC=1 可改發未公證的 ad-hoc 版本
#   draft    以 dist/release/X.Y.Z/ 的產物建立或更新 GitHub Release 草稿（需 gh 登入或 GH_TOKEN）
#   release  下載草稿附件驗證 SHA-256、簽章、公證與版本後，正式發佈並標為 Latest（repo 首頁可見）
#   tap      以已正式發佈的 vX.Y.Z 附件雜湊產生 Homebrew cask（packaging/homebrew/），推到 tap repo
#            （MACMEOW_TAP_REPO）；CI 用 HOMEBREW_TAP_TOKEN，本機用 gh 的登入
#
# CI 會直接正式發佈，所以 publish 之前必須以本機 build 的產物手動冒煙測試（見 docs/release.md「冒煙測試」）。
set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
load_env # MACMEOW_SIGN_ID／MACMEOW_NOTARY_PROFILE（.env）；build 從 tag 建置時以環境變數傳給 build-app.sh
cd "$ROOT"

ver_valid() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; }
# ver_gt a b：a > b
ver_gt() {
  local IFS=. a b i
  read -r -a a <<<"$1"
  read -r -a b <<<"$2"
  for i in 0 1 2; do
    ((a[i] > b[i])) && return 0
    ((a[i] < b[i])) && return 1
  done
  return 1
}

tag_exists() { git rev-parse -q --verify "refs/tags/v$1" >/dev/null; }
need_gh() { need_cmd gh; }
# release_is_draft <X.Y.Z>：輸出 GitHub Release 的 isDraft（true／false）；沒有該 Release 時回傳非 0。
release_is_draft() { gh release view "v$1" --json isDraft --jq .isDraft 2>/dev/null; }
release_url() { gh release view "v$1" --json url --jq .url; }

# changelog_section <標題>：輸出 CHANGELOG.md 中該 `## ` 標題下的內容（不含標題）
changelog_section() {
  awk -v h="## $1" 'f && /^## /{exit} f{print} index($0, h)==1 && (length($0)==length(h) || substr($0, length(h)+1, 1)==" "){f=1}' CHANGELOG.md
}

# 發佈版本預設必須 Developer ID 簽章並公證（見 docs/signing.md）
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

# Homebrew cask
CASK_TEMPLATE="packaging/homebrew/$MACMEOW_CASK.rb"

# render_cask <X.Y.Z> <sha256> <輸出檔>：以範本產生 cask
render_cask() {
  [[ "$2" =~ ^[0-9a-f]{64}$ ]] || die "SHA-256 格式不正確：$2"
  sed -e "s/@VERSION@/$1/g" -e "s/@SHA256@/$2/g" "$ROOT/$CASK_TEMPLATE" >"$3"
  if grep -n '@[A-Z0-9]*@' "$3"; then die "cask 範本有未取代的佔位符"; fi
}

# style_cask <cask 檔>：有 Homebrew 時以 brew style 檢查（cask 檔需位於 Casks/ 資料夾，才會套用 cask 規則）
style_cask() {
  local out
  if ! command -v brew >/dev/null; then
    echo "  ! 沒有 Homebrew，略過 brew style"
    return
  fi
  out="$(brew style "$1" 2>&1)" || {
    echo "$out" >&2
    die "brew style 有警告：${CASK_TEMPLATE}"
  }
  ok "brew style（${CASK_TEMPLATE}）"
}

# check_repo <X.Y.Z>：版本號遞增、在 main 且工作目錄乾淨、tag 不存在、Unreleased 有內容
check_repo() {
  local v="$1" cur branch n
  cur="$(cat VERSION)"
  ver_gt "$v" "$cur" || die "新版本 ${v} 必須大於目前的 VERSION ${cur}"
  ok "版本 ${cur} → ${v}"

  branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
  [[ "$branch" == "main" ]] || die "請在 main 分支發佈（目前：${branch:-detached}）"
  [[ -z "$(git status --porcelain)" ]] || die "工作目錄有未提交的變更"
  ok "main、工作目錄乾淨"

  tag_exists "$v" && die "tag v${v} 已存在"
  ok "tag v${v} 尚未存在"

  n="$(changelog_section Unreleased | grep -c '^- ' || true)"
  ((n > 0)) || die "CHANGELOG.md 的 ## Unreleased 沒有任何項目"
  ok "Unreleased 有 ${n} 項"
}

# check_sources：腳本語法與 shellcheck、App 編譯與 Core 單元測試、Wine DLL 雜湊
check_sources() {
  local f bad=0
  while IFS= read -r f; do bash -n "$f" || bad=1; done < <(git ls-files '*.sh')
  ((bad == 0)) || die "bash -n 失敗"
  ok "bash -n（$(git ls-files '*.sh' | wc -l | tr -d ' ') 個腳本）"
  if command -v shellcheck >/dev/null; then
    git ls-files 'scripts/*.sh' 'app/*.sh' | xargs shellcheck -x -S warning || die "shellcheck 有警告"
    ok "shellcheck（scripts/、app/）"
  fi
  bash "$ROOT/tools/dev/lint.sh" app || die "App 編譯失敗或有警告（bash tools/dev/lint.sh app）"
  ok "App 編譯無警告（tools/dev/lint.sh app）"
  bash "$ROOT/tools/dev/test-app.sh" >/dev/null || die "app/Sources/Core 單元測試失敗（bash tools/dev/test-app.sh）"
  ok "Core 單元測試（tools/dev/test-app.sh）"

  (cd patches/bin/x86_64-windows && shasum -a 256 -c ../SHA256SUMS >/dev/null) || die "patches/bin/SHA256SUMS 與 DLL 不符"
  ok "patches/bin/SHA256SUMS"
}

# check_cask <X.Y.Z>：cask 範本填入假雜湊後通過 brew style
check_cask() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir "$tmp/Casks"
  render_cask "$1" "$(printf '%064d' 0)" "$tmp/Casks/$MACMEOW_CASK.rb"
  style_cask "$tmp/Casks/$MACMEOW_CASK.rb"
  rm -rf "$tmp"
}

cmd_check() {
  echo "發佈前檢查 ${1}："
  check_repo "$1"
  check_sources
  check_cask "$1"
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
  MACMEOW_RELEASE=1 git commit -q -m "chore(release): $v" -m "Move the Unreleased changelog entries under $v and set VERSION to $v."
  git tag -a "v$v" -m "MacMeow $v"
  echo "已建立 commit「chore(release): ${v}」與 tag v${v}（尚未 push）。"
  echo "下一步：bash tools/release/release.sh build ${v} 並冒煙測試，再 publish ${v}（push 後由 GitHub Actions 建置並正式發佈）"
}

# stapler_validate <檔案>：確認檔案釘有有效的公證票證。從耗時看來 stapler validate 會連線 Apple：
# v0.6.0 CI 的 release 步驟驗證下載的草稿附件時，validate 花了約 7 秒後失敗（正常不到 1 秒），而 SHA-256
# 相同的同一個 dmg 一分鐘前在 build 步驟才通過，所以視為暫時性的網路問題，間隔漸增重試（共約 1.5 分鐘）；
# 最後一次不加 -q，失敗原因才會出現在 log。
stapler_validate() {
  local i
  for i in 1 2 3; do
    xcrun stapler validate -q "$1" && return
    echo "  ! 公證票證驗證失敗，$((i * 15)) 秒後重試：$(basename "$1")" >&2
    sleep $((i * 15))
  done
  xcrun stapler validate "$1"
}

# verify_dmg <dmg> <X.Y.Z>：dmg（非 ad-hoc 時）已簽章、公證；掛載後 App 簽章有效、已公證且 Gatekeeper 認可、
# 符合一鍵更新的簽章需求、版本正確
verify_dmg() {
  local dmg="$1" v="$2" chk mnt
  if ! adhoc_release; then
    codesign --verify "$dmg" || die "dmg 簽章驗證失敗"
    stapler_validate "$dmg" || die "dmg 沒有公證票證"
    spctl --assess --type open --context context:primary-signature -vv "$dmg" 2>&1 \
      | grep 'source=Notarized Developer ID' >/dev/null \
      || die "Gatekeeper 未認可 dmg（spctl --assess --type open --context context:primary-signature -vv）"
    ok "dmg：Notarized Developer ID"
  fi
  chk="$(mktemp -d)"
  mnt="$chk/mnt"
  dmg_attach --nobrowse --readonly --mountpoint "$mnt" "$dmg" >/dev/null || die "無法掛載 ${dmg}"
  ditto "$mnt/MacMeow.app" "$chk/MacMeow.app"
  [[ -L "$mnt/應用程式" && -f "$mnt/.DS_Store" && -f "$mnt/.background/background.tiff" ]] \
    || {
      hdiutil detach -quiet "$mnt"
      die "dmg 內缺少「應用程式」捷徑或視窗版面（.DS_Store、背景圖）"
    }
  hdiutil detach -quiet "$mnt" || die "無法卸載 ${mnt}"
  codesign --verify --deep --strict "$chk/MacMeow.app" || die "dmg 內 App 簽章驗證失敗"
  ok "codesign"
  # Homebrew cask 的 uninstall script 寫死這個路徑；缺少時 brew uninstall／upgrade 都會失敗
  [[ -x "$chk/MacMeow.app/Contents/Resources/scripts/uninstall.sh" ]] \
    || die "dmg 內 App 缺少可執行的 Contents/Resources/scripts/uninstall.sh（cask 依賴）"
  ok "App：scripts/uninstall.sh"
  if ! adhoc_release; then
    stapler_validate "$chk/MacMeow.app" || die "dmg 內 App 沒有公證票證"
    spctl --assess --type exec -vv "$chk/MacMeow.app" 2>&1 | grep 'source=Notarized Developer ID' >/dev/null \
      || die "Gatekeeper 未認可 dmg 內 App（spctl --assess --type exec -vv）"
    ok "App：Notarized Developer ID"
    # 舊版 App 的一鍵更新（scripts/update.sh）只接受符合 MACMEOW_REQUIREMENT 的新版
    codesign --verify -R="$MACMEOW_REQUIREMENT" "$chk/MacMeow.app" \
      || die "App 不是以 Team ID ${MACMEOW_TEAM_ID} 簽章，舊版 App 將無法一鍵更新（scripts/lib/common.sh）"
    ok "App：Team ID ${MACMEOW_TEAM_ID}"
  else
    echo "注意：ad-hoc 版本無法透過 App 的一鍵更新安裝，使用者需手動下載"
  fi
  [[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$chk/MacMeow.app/Contents/Info.plist")" == "$v" ]] \
    || die "dmg 內 App 版本不是 ${v}"
  ok "App 版本 ${v}"
  rm -rf "$chk"
}

cmd_build() {
  local v="$1" src out dmg lgpl
  tag_exists "$v" || die "找不到 tag v${v}，請先執行 prepare"
  src="$ROOT/build/release/$v"
  out="$ROOT/dist/release/$v"
  rm -rf "$src" "$out"
  mkdir -p "$src" "$out"

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
  (cd "$out" && shasum -a 256 "$dmg" >"$dmg.sha256")

  verify_dmg "$out/$dmg" "$v"

  # LGPL 原始碼清單＝patches/SOURCES.md 第一個頂層「- 」清單，到下一個空行為止（清單中間不能有空行）。
  # 在寫入 release-notes.md 之前取出，找不到就中止，不產生缺少授權資訊的說明。
  lgpl="$(awk '/^- /{f=1} f && /^$/{exit} f' "$src/patches/SOURCES.md")"
  [[ -n "$lgpl" ]] || die "patches/SOURCES.md 找不到 LGPL 原始碼清單"

  {
    changelog_section "$v" | awk 'NF{for(;b>0;b--)print ""; s=1; print; next} s{b++}' # 去掉頭尾空行
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
    printf '%s\n' "$lgpl"
  } >"$out/release-notes.md"

  echo "產物：$out"
  ls -1 "$out" | sed 's/^/  /'
  [[ -n "${GITHUB_ACTIONS:-}" ]] \
    || echo "請先冒煙測試 ${out}/${dmg}；正式發佈用 publish（由 CI 建置），CI 無法使用時改用 draft ${v} 與 release ${v}"
}

cmd_publish() {
  local v="$1"
  tag_exists "$v" || die "找不到 tag v${v}，請先執行 prepare"
  git remote get-url origin >/dev/null 2>&1 || die "尚未設定 git remote origin"
  [[ "$(git rev-parse "v$v^{commit}")" == "$(git rev-parse main)" ]] || echo "注意：tag v${v} 不是 main 的最新 commit"
  git push --atomic origin main "v$v" # 兩者同時成功或同時失敗
  echo "已 push。GitHub Actions 會建置、簽章、公證並正式發佈 Release（gh run watch 或 repo 的 Actions 頁面）。"
}

cmd_ci() {
  local v="$1"
  echo "CI 發佈 ${v}："
  tag_exists "$v" || die "找不到 tag v${v}"
  [[ "$(git show "v$v:VERSION")" == "$v" ]] || die "tag v${v} 的 VERSION 不是 ${v}"
  git show "v$v:CHANGELOG.md" | grep "^## $v " >/dev/null || die "tag v${v} 的 CHANGELOG.md 沒有 ## ${v} 段落"
  ok "VERSION 與 CHANGELOG"
  git fetch -q origin main
  git merge-base --is-ancestor "v$v^{commit}" FETCH_HEAD || die "tag v${v} 不在 origin/main 上"
  ok "tag v${v} 在 origin/main 上"
  cmd_build "$v"
  cmd_draft "$v"
  cmd_release "$v"
  # Release 已公開；tap 更新失敗時 CI 標為失敗，修正後在本機重跑 tap
  echo "（Homebrew tap 更新失敗時 Release 已發佈：修正後執行 bash tools/release/release.sh tap ${v}）"
  cmd_tap "$v"
}

cmd_draft() {
  local v="$1" out="$ROOT/dist/release/$1" state
  local assets=("$out/MacMeow-$v.dmg" "$out/MacMeow-$v.dmg.sha256")
  [[ -f "${assets[0]}" && -f "${assets[1]}" && -f "$out/release-notes.md" ]] || die "找不到 ${out} 的產物，請先執行 build"
  need_gh
  if state="$(release_is_draft "$v")"; then
    [[ "$state" == true ]] || die "v${v} 已正式發佈，不覆蓋；請改發下一個 patch 版本"
    gh release upload "v$v" --clobber "${assets[@]}"
    gh release edit "v$v" --title "MacMeow $v" --notes-file "$out/release-notes.md"
    echo "已更新 GitHub Release 草稿 v${v}"
  else
    gh release create "v$v" --draft --verify-tag --title "MacMeow $v" \
      --notes-file "$out/release-notes.md" "${assets[@]}"
    echo "已建立 GitHub Release 草稿 v${v}"
  fi
  [[ -n "${GITHUB_ACTIONS:-}" ]] || echo "冒煙測試通過後：bash tools/release/release.sh release ${v}"
}

cmd_release() {
  local v="$1" dmg="MacMeow-$1.dmg" state tmp
  need_gh
  echo "正式發佈 ${v}："
  state="$(release_is_draft "$v")" \
    || die "GitHub 上沒有 v${v} 的 Release，請先 publish（CI 建立草稿）或 draft"
  if [[ "$state" != true ]]; then
    echo "v${v} 已正式發佈：$(release_url "$v")"
    return
  fi
  ok "草稿 v${v} 存在"

  # 驗證的是使用者實際會下載的附件，而非本機 dist/
  tmp="$(mktemp -d)"
  gh release download "v$v" --pattern "$dmg" --pattern "$dmg.sha256" -D "$tmp"
  (cd "$tmp" && shasum -a 256 -c "$dmg.sha256" >/dev/null) || die "${dmg} 與 ${dmg}.sha256 不符"
  ok "SHA-256"
  verify_dmg "$tmp/$dmg" "$v"
  rm -rf "$tmp"

  gh release edit "v$v" --draft=false --latest >/dev/null
  echo "已正式發佈 v${v}（Latest）：$(release_url "$v")"
}

# cmd_tap <X.Y.Z>：以正式版附件的 SHA-256 產生 cask，推到 tap repo（版本相同時不 commit；不降版）
cmd_tap() {
  local v="$1" tmp sha token header cask cur tap who=()
  need_gh
  tap="${MACMEOW_TAP_REPO%%/*}/${MACMEOW_TAP_REPO#*/homebrew-}"
  echo "更新 Homebrew tap ${tap}（${MACMEOW_TAP_REPO}）："
  [[ "$(release_is_draft "$v")" == false ]] \
    || die "v${v} 尚未正式發佈（cask 只指向正式版的附件）"
  tmp="$(mktemp -d)"
  # 雜湊取自使用者實際下載的附件，而非本機 dist/
  gh release download "v$v" --pattern "MacMeow-$v.dmg.sha256" -D "$tmp"
  sha="$(cut -d' ' -f1 "$tmp/MacMeow-$v.dmg.sha256")"
  ok "MacMeow-${v}.dmg SHA-256 ${sha}"

  token="${HOMEBREW_TAP_TOKEN:-}"
  if [[ -z "$token" ]]; then
    [[ -z "${GITHUB_ACTIONS:-}" ]] || die "CI 需要 Secret HOMEBREW_TAP_TOKEN（見 docs/ci.md「Secrets」）"
    token="$(gh auth token)" || die "請先 gh auth login"
  fi
  # token 只放在這次 git 指令的 HTTP header，不寫進 clone 的 .git/config
  header="http.https://github.com/.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')"
  git -c "$header" clone -q --depth 1 "https://github.com/$MACMEOW_TAP_REPO.git" "$tmp/tap" \
    || die "無法 clone ${MACMEOW_TAP_REPO}（token 需要該 repo 的 Contents 讀寫權限）"
  cask="$tmp/tap/Casks/$MACMEOW_CASK.rb"
  mkdir -p "$tmp/tap/Casks"
  if [[ -f "$cask" ]]; then
    cur="$(sed -n 's/^  version "\(.*\)"$/\1/p' "$cask")"
    if ver_valid "$cur" && ver_gt "$cur" "$v"; then die "tap 已是較新的版本 ${cur}"; fi
  fi
  render_cask "$v" "$sha" "$cask"
  style_cask "$cask"

  if [[ -z "$(git -C "$tmp/tap" status --porcelain)" ]]; then
    echo "tap 已是 ${v}，不需更新"
  else
    # CI 以 github-actions[bot] commit；本機沿用本 repo 的作者設定（暫存 clone 沒有）
    if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
      who=(-c "user.name=github-actions[bot]" -c "user.email=41898282+github-actions[bot]@users.noreply.github.com")
    else
      who=(-c "user.name=$(git config user.name)" -c "user.email=$(git config user.email)")
    fi
    git -C "$tmp/tap" add Casks
    git -C "$tmp/tap" ${who[@]+"${who[@]}"} commit -q -m "$MACMEOW_CASK $v"
    git -C "$tmp/tap" -c "$header" push -q origin HEAD
    echo "已更新 ${tap}/${MACMEOW_CASK} 為 ${v}"
  fi
  rm -rf "$tmp"
}

(($# == 2)) || usage_doc
ver_valid "$2" || die "版本格式需為 X.Y.Z：$2"
case "$1" in
  check | prepare | build | publish | ci | draft | release | tap) "cmd_$1" "$2" ;;
  *) usage_doc ;;
esac
