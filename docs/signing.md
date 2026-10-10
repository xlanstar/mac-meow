# 簽章與公證

Developer ID 簽章與 Apple 公證的一次性設定、`build-app.sh` 的簽章行為與疑難排解；只有第一次設定、更換憑證或公證失敗時才需要，發佈流程見 [release.md](release.md)。

`app/build-app.sh` 預設只做 ad-hoc 簽章：本機建置的 App 沒有 quarantine 標記，自己用沒問題；但從網路下載的 ad-hoc App 會被 Gatekeeper 擋下，所以發佈版本必須用 Developer ID 簽章並送 Apple 公證。

## 一次性設定

需 Apple Developer Program 帳號；本機範本是 `.env.example`。

1. 建立 **Developer ID Application** 憑證（只有帳號持有人能建立；`Apple Development` 憑證不能用於發佈）：
   - Xcode：Settings → Accounts → Manage Certificates → `+`。
   - Xcode 無法建立時改用網站：以 `openssl req -new -newkey rsa:2048 -nodes -keyout devid.key -out devid.csr -subj "/CN=MacMeow Developer ID"` 產生 CSR，到 [Certificates](https://developer.apple.com/account/resources/certificates/add) 選 Developer ID Application（G2 Sub-CA）上傳；下載 `.cer` 後與私鑰合成 `.p12`（`/usr/bin/openssl pkcs12 -export`）再 `security import` 到登入鑰匙圈，最後刪除私鑰檔。
   - 確認：`security find-identity -v -p codesigning`。
2. 在 [appleid.apple.com](https://appleid.apple.com) 建立 App 專用密碼，存成 notarytool profile：
   ```sh
   xcrun notarytool store-credentials macmeow-notary --apple-id <Apple ID> --team-id <Team ID> --password <App 專用密碼>
   ```
3. `cp .env.example .env`，填入 `MACMEOW_SIGN_ID` 與 `MACMEOW_NOTARY_PROFILE`（第 2 步的 profile 名稱）；各鍵說明見 `.env.example`。`.env` 已列入 `.gitignore`，不提交。
   - 已存在的環境變數優先於 `.env`（`tools/lib.sh` 的 `load_env`），例如 `MACMEOW_NOTARY_PROFILE= bash app/build-app.sh` 只簽章不公證。

## `build-app.sh` 的簽章行為

三種設定（ad-hoc／只簽章／簽章＋公證）的行為見 `app/build-app.sh` 開頭註解。公證時 App 與 dmg 各公證一次並釘上票證，兩者離線都能通過 Gatekeeper。

## 細節與疑難排解

公證失敗時，依 `build-app.sh` 印出的 `xcrun notarytool log` 指令查看原因。

CI 的 Secrets 何時要重設見 [ci.md](ci.md#secrets)。
