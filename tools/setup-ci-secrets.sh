#!/bin/bash
# 一次設定 GitHub Actions 發佈需要的 Secrets（見 docs/development.md「GitHub Actions」）。
# 從鑰匙圈匯出 MACMEOW_SIGN_ID 指定的 Developer ID Application 身分（憑證＋私鑰），
# 重新打包成只含這一張的 .p12（隨機密碼），詢問並驗證公證用的 Apple ID 與 App 專用密碼，
# 再以 gh secret set 寫入目前 repo。暫存檔在結束時刪除，密碼不會顯示或寫到磁碟。
#
# 用法：bash tools/setup-ci-secrets.sh [--dry-run]
#   --dry-run  只匯出並檢查 .p12，不詢問 Apple 帳密、不寫入 GitHub
# 需要：在終端機執行、gh auth login、repo 已設定 GitHub origin、.env 的 MACMEOW_SIGN_ID。
# macOS 會跳出視窗詢問是否允許匯出鑰匙圈項目：輸入登入密碼並按「允許」（每個簽章身分一次）。
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"
load_env

OPENSSL=/usr/bin/openssl # 系統 LibreSSL：讀得懂 security export 的格式，產生的 .p12 也能被 security import 匯入
DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *)
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac
SIGN_ID="${MACMEOW_SIGN_ID:-}"
# 測試用：從其他鑰匙圈匯出
KEYCHAIN="${MACMEOW_EXPORT_KEYCHAIN:-$(security login-keychain | sed 's/^[[:space:]]*"//; s/"[[:space:]]*$//')}"

ok() { echo "  ✓ $*"; }

# ---- 1. 先檢查 GitHub 端，避免匯出私鑰後才失敗
repo=""
if ((! DRY_RUN)); then
  [[ -t 0 ]] || die "請在終端機執行（需要輸入 Apple 帳密）"
  command -v gh >/dev/null || die "需要 gh（brew install gh）"
  gh auth status >/dev/null 2>&1 || die "請先 gh auth login"
  repo="$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)" \
    || die "找不到 GitHub repo：請先建立 repo 並設定 origin（例如 gh repo create <名稱> --private --source .）"
  ok "GitHub repo：${repo}"
fi

tmp="$(mktemp -d)"
chmod 700 "$tmp"
trap 'rm -Prf "$tmp"' EXIT

# ---- 2. 匯出所有簽章身分，挑出目標憑證與對應私鑰
echo "從鑰匙圈匯出簽章身分（macOS 會詢問是否允許，請輸入登入密碼並按「允許」）⋯"
export_pw="$($OPENSSL rand -hex 24)"
if ! err="$(security export -k "$KEYCHAIN" -t identities -f pkcs12 -P "$export_pw" -o "$tmp/all.p12" 2>&1 >/dev/null)"; then
  die "鑰匙圈匯出失敗（是否按了「拒絕」？）：${err}"
fi
$OPENSSL pkcs12 -in "$tmp/all.p12" -passin "pass:$export_pw" -nodes -out "$tmp/all.pem" 2>/dev/null \
  || die "無法解析匯出的 .p12"
rm -P "$tmp/all.p12"
awk -v d="$tmp" '/^-----BEGIN /{n++; f=sprintf("%s/b%03d.pem", d, n)} f{print > f} /^-----END /{close(f); f=""}' "$tmp/all.pem"
rm -P "$tmp/all.pem"

cert="" cn="" fp=""
for b in "$tmp"/b*.pem; do
  [[ -e "$b" ]] || continue
  grep -q -- '-----BEGIN CERTIFICATE-----' "$b" || continue
  c="$($OPENSSL x509 -in "$b" -noout -subject | sed -n 's|.*/CN=\(Developer ID Application: [^/]*\).*|\1|p')"
  [[ -n "$c" ]] || continue
  f="$($OPENSSL x509 -in "$b" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
  if [[ -z "$SIGN_ID" || "$SIGN_ID" == "$f" || "$SIGN_ID" == "$c" ]]; then
    [[ -z "$cert" || "$f" == "$fp" ]] || die "找到多張 Developer ID Application 憑證，請在 .env 設定 MACMEOW_SIGN_ID 為其中一張的 SHA-1"
    cert="$b" cn="$c" fp="$f"
  fi
done
[[ -n "$cert" ]] || die "鑰匙圈中找不到 Developer ID Application 憑證${SIGN_ID:+（MACMEOW_SIGN_ID=${SIGN_ID}）}"
$OPENSSL x509 -in "$cert" -noout -checkend 0 >/dev/null || die "憑證已過期：${cn}"

pub="$($OPENSSL x509 -in "$cert" -noout -pubkey)"
key=""
for b in "$tmp"/b*.pem; do
  grep -q -- 'PRIVATE KEY-----' "$b" || continue
  [[ "$($OPENSSL pkey -in "$b" -pubout 2>/dev/null)" == "$pub" ]] && {
    key="$b"
    break
  }
done
[[ -n "$key" ]] || die "找不到 ${cn} 的私鑰（憑證必須和私鑰在同一個鑰匙圈）"

team="$($OPENSSL x509 -in "$cert" -noout -subject | sed -n 's|.*/OU=\([^/]*\).*|\1|p')"
expiry="$($OPENSSL x509 -in "$cert" -noout -enddate | sed 's/^notAfter=//')"
ok "憑證：${cn}"
ok "SHA-1：${fp}，Team ID：${team}，到期：${expiry}"

# ---- 3. 重新打包成只含這一張的 .p12
p12_pw="$($OPENSSL rand -base64 32 | tr -d '\n')"
$OPENSSL pkcs12 -export -inkey "$key" -in "$cert" -name "$cn" \
  -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1 \
  -passout "pass:$p12_pw" -out "$tmp/devid.p12"
rm -P "$tmp"/b*.pem
n="$($OPENSSL pkcs12 -in "$tmp/devid.p12" -passin "pass:$p12_pw" -nodes 2>/dev/null | grep -c -- '-----BEGIN ' || true)"
[[ "$n" == 2 ]] || die ".p12 內容不正確（預期 1 張憑證＋1 把私鑰，實際 ${n} 個項目）"
ok ".p12 只含這張憑證與私鑰（$(wc -c <"$tmp/devid.p12" | tr -d ' ') bytes）"

if ((DRY_RUN)); then
  echo "dry-run：未寫入 GitHub。"
  exit 0
fi

# ---- 4. Apple 公證帳密
echo
echo "公證用的 Apple 帳號（App 專用密碼在 https://account.apple.com →「登入與安全性」→「App 專用密碼」建立）："
read -r -p "  Apple ID：" apple_id
[[ -n "$apple_id" ]] || die "Apple ID 不能是空的"
read -r -s -p "  App 專用密碼（輸入時不顯示）：" app_pw
echo
[[ -n "$app_pw" ]] || die "App 專用密碼不能是空的"
echo "驗證 Apple 帳密⋯"
xcrun notarytool history --apple-id "$apple_id" --team-id "$team" --password "$app_pw" >/dev/null 2>&1 \
  || die "無法以這組 Apple ID／App 專用密碼登入公證服務（Team ID ${team}）"
ok "Apple 帳密可登入公證服務"

# ---- 5. 寫入 GitHub Secrets
echo
read -r -p "寫入 ${repo} 的 Actions Secrets（同名者會被覆蓋），繼續？[y/N] " yn
[[ "$yn" == [yY] ]] || die "已取消，未寫入任何 Secret"
set_secret() {
  printf '%s' "$2" | gh secret set "$1" --repo "$repo" >/dev/null
  ok "$1"
}
set_secret DEVELOPER_ID_P12_BASE64 "$(base64 -i "$tmp/devid.p12")"
set_secret DEVELOPER_ID_P12_PASSWORD "$p12_pw"
set_secret APPLE_ID "$apple_id"
set_secret APPLE_TEAM_ID "$team"
set_secret APPLE_APP_PASSWORD "$app_pw"
echo "完成。之後 bash tools/release.sh publish X.Y.Z 即由 GitHub Actions 建置並建立 Release 草稿。"
