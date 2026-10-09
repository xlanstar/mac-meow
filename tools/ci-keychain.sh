#!/bin/bash
# GitHub Actions 發佈用：建立暫時鑰匙圈，匯入 Developer ID 憑證與 notarytool 帳密。
# 只在 CI（GITHUB_ACTIONS=true）執行，會改動目前使用者的鑰匙圈搜尋清單。
#
# 用法：bash tools/ci-keychain.sh setup|cleanup
#   setup    需要環境變數（來自 GitHub Secrets）：
#              DEVELOPER_ID_P12_BASE64、DEVELOPER_ID_P12_PASSWORD、
#              APPLE_ID、APPLE_TEAM_ID、APPLE_APP_PASSWORD
#            成功後把 MACMEOW_SIGN_ID／MACMEOW_NOTARY_PROFILE／MACMEOW_NOTARY_KEYCHAIN 寫入 $GITHUB_ENV
#   cleanup  刪除暫時鑰匙圈（同時從搜尋清單移除）
set -euo pipefail

die() { echo "錯誤：$*" >&2; exit 1; }
[[ "${GITHUB_ACTIONS:-}" == true ]] || die "只能在 GitHub Actions 執行"
[[ -n "${RUNNER_TEMP:-}" && -n "${GITHUB_ENV:-}" ]] || die "缺少 RUNNER_TEMP／GITHUB_ENV"

KC="$RUNNER_TEMP/macmeow-signing.keychain-db"
PROFILE="macmeow-notary"
# Developer ID G2 中繼憑證；runner 通常已內建，匯入一份避免憑證鏈不完整
G2_URL="https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer"

setup() {
  local v kc_pw p12 g2 id k
  for v in DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD; do
    [[ -n "${!v:-}" ]] || die "缺少 Secret：${v}"
  done

  kc_pw="$(openssl rand -hex 24)"
  echo "::add-mask::$kc_pw"
  security create-keychain -p "$kc_pw" "$KC"
  security set-keychain-settings -lut 21600 "$KC"   # 6 小時後自動上鎖
  security unlock-keychain -p "$kc_pw" "$KC"

  p12="$RUNNER_TEMP/devid.p12"
  ( umask 077; printf '%s' "$DEVELOPER_ID_P12_BASE64" | base64 -D >"$p12" )
  security import "$p12" -k "$KC" -f pkcs12 -P "$DEVELOPER_ID_P12_PASSWORD" -T /usr/bin/codesign >/dev/null
  rm -f "$p12"
  g2="$RUNNER_TEMP/DeveloperIDG2CA.cer"
  curl -fsSL -o "$g2" "$G2_URL"
  security import "$g2" -k "$KC" >/dev/null 2>&1 || true
  rm -f "$g2"
  # 允許 codesign 不經 UI 授權使用私鑰（CI 沒有 UI，否則會卡住）
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$kc_pw" "$KC" >/dev/null

  # 加到搜尋清單最前面（保留原有鑰匙圈），codesign 才找得到身分
  local list=("$KC")
  while IFS= read -r k; do
    k="${k#"${k%%[![:space:]]*}"}"; k="${k#\"}"; k="${k%\"}"
    [[ -n "$k" && "$k" != "$KC" ]] && list+=("$k")
  done < <(security list-keychains -d user)
  security list-keychains -d user -s "${list[@]}"

  id="$(security find-identity -v -p codesigning "$KC" | awk '/"Developer ID Application: /{print $2; exit}')"
  [[ -n "$id" ]] || die "p12 內沒有有效的 Developer ID Application 身分"
  echo "簽章身分：$(security find-identity -v -p codesigning "$KC" | awk -F'"' '/Developer ID Application: /{print $2; exit}')"

  xcrun notarytool store-credentials "$PROFILE" --keychain "$KC" \
    --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD" >/dev/null
  echo "公證帳密：已驗證並存入暫時鑰匙圈"

  {
    echo "MACMEOW_SIGN_ID=$id"
    echo "MACMEOW_NOTARY_PROFILE=$PROFILE"
    echo "MACMEOW_NOTARY_KEYCHAIN=$KC"
  } >>"$GITHUB_ENV"
}

cleanup() {
  [[ -f "$KC" ]] || return 0
  security delete-keychain "$KC"
  echo "已刪除暫時鑰匙圈"
}

case "${1:-}" in
  setup)   setup ;;
  cleanup) cleanup ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
