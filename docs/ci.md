# CI

GitHub Actions 的發佈 workflow、Dependabot 與 repo 的 Actions Secrets；發佈流程本身見 [release.md](release.md)。

## 發佈 workflow

`.github/workflows/release.yml` 在 push `vX.Y.Z` tag 時執行（步驟見該檔，暫時鑰匙圈見 `tools/release/ci-keychain.sh` 開頭），由 `release.sh ci` 建置、公證、正式發佈並更新 Homebrew tap（見 [release.md](release.md#流程)）。

- Swift 工具鏈以 runner 映像的 Xcode 為準。
- GitHub 的 macOS runner 有 Aqua 工作階段與「自動化」權限，所以能執行 dmg 的 Finder 排版（見 [app.md](app.md#建置與-dmg)）。

## Dependabot

`.github/dependabot.yml` 只追蹤 GitHub Actions（範圍、排程與冷卻期見該檔）。prek hook 版本以 `prek update` 手動更新（見 [development.md](development.md#提交前檢查prek)）。

## Secrets

- 簽章與公證用的 5 個 Secret：在已設定 GitHub `origin` 且已執行 `gh auth login` 的終端機執行 `just setup-ci-secrets`，一次寫入（名稱見 `release.yml` 的 `env` 與 `ci-keychain.sh` 開頭，行為見 `setup-ci-secrets.sh` 開頭）。
  - 公證建議用一組 CI 專用的 App 專用密碼，方便撤銷。
  - 憑證到期或更換、App 專用密碼撤銷時重跑一次。
- `HOMEBREW_TAP_TOKEN` 另外設定：在 [Fine-grained tokens](https://github.com/settings/personal-access-tokens/new) 建立 token，Repository access 只選 tap repo（`common.sh` 的 `MACMEOW_TAP_REPO`），Repository permissions 的 Contents 設為 Read and write（其餘不給），再執行 `gh secret set HOMEBREW_TAP_TOKEN` 貼上。Token 到期後重建並重設。
