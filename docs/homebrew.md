# Homebrew

Homebrew cask（`brew install --cask xlanstar/tap/macmeow`）的範本、安裝／升級／移除時的行為，以及發佈到 tap 的方式。

## Cask 範本

`packaging/homebrew/macmeow.rb` 是 cask 範本（由 `release.sh tap` 填入版本與雜湊），發佈到第三方 tap [`xlanstar/homebrew-tap`](https://github.com/xlanstar/homebrew-tap)（`common.sh` 的 `MACMEOW_TAP_REPO`）。tap 的 `Casks/` 只由 `release.sh tap` 產生，不直接修改；要改 cask 就改範本。

## 安裝與移除

- 安裝時 cask 把 App 內的 `scripts/` 複製到 Caskroom，移除時執行那一份 `uninstall.sh cask`（做法見 `macmeow.rb` 註解）；因此使用者自行刪除 App 後 `brew uninstall` 仍能還原，前提是 `uninstall.sh` 的還原只用到 `scripts/` 內的檔案（見 [scripts.md](scripts.md#uninstallsh)）。
- `cask` 子指令：Homebrew 的 upgrade、reinstall、install 也會執行 cask 的 uninstall 區塊，`uninstall.sh cask` 這時什麼都不做（判斷方式見 `uninstall.sh` 的 `brew_subcommand`）。
  - 判斷不出時的後果：每次 `brew upgrade` 都會還原修補、刪除 App 設定並要求密碼。
- `zap`：列出 `uninstall.sh` 刪除的 LaunchDaemon 與 App 的設定、快取、記錄（對應 [external-state.md](external-state.md#清單)）。
- App 由 cask 安裝時，App 內的一鍵更新與「解除安裝…」改為顯示對應的 `brew` 指令，交給 brew 處理（`brew-command`；判斷方式見 `common.sh` 的 `homebrew_app`）。

## 發佈到 tap

`release.sh tap X.Y.Z`（CI 在 Release 正式發佈後由 `ci` 呼叫）：

- 行為見 `release.sh` 的 `cmd_tap`（只用已正式發佈的附件、不降版、內容沒變不 commit）。
- cask 改了但版本不變時（例如改 `zap`），可直接重跑最新版的 `tap`。
- CI 以 `HOMEBREW_TAP_TOKEN`（見 [ci.md](ci.md#secrets)）、本機以 `gh auth token` 存取 tap repo。

發佈後驗證：`brew audit --cask --online xlanstar/tap/macmeow`（`--new` 的知名度門檻只適用官方 repo，可忽略）。
