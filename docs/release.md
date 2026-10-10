# 發佈

版本號、以 `tools/release/release.sh`（`just release`）發佈的流程、冒煙測試與失敗處理。簽章與公證的一次性設定見 [signing.md](signing.md)，GitHub Actions 與 Secrets 見 [ci.md](ci.md)，Homebrew cask 見 [homebrew.md](homebrew.md)。

## 版本號

`VERSION` 採 SemVer `X.Y.Z`，tag 為 `vX.Y.Z`。1.0 之前：

- `Z`（patch）：修正，使用者不需要做任何事。
- `Y`（minor）：新功能、支援新的 Cyder engine／CrossOver 基底（重建 DLL）、私服位址變更（使用者需重新設定迴路位址：`setup-loopback.sh install`，需密碼）、外部狀態的種類有變。
- 使用者需要手動處理的變更，在 CHANGELOG 該項目寫清楚要做什麼。

## 流程

每一步都可以單獨重跑；各子指令的用途見 `release.sh` 開頭：

```sh
just release check   X.Y.Z   # 只檢查，不修改
just release prepare X.Y.Z   # 改 CHANGELOG／VERSION，commit「chore(release): X.Y.Z」+ tag vX.Y.Z（不 push）
just release build   X.Y.Z   # 本機從 tag 建置 → dist/release/X.Y.Z/，push 前必須冒煙測試
just release publish X.Y.Z   # push main + tag → CI 建置、簽章、公證、正式發佈（Latest）並更新 Homebrew tap
gh run watch                 # 等 CI 完成
```

- `check`：發佈前檢查（項目見 `release.sh` 開頭與 `cmd_check`）。
  - 例外：`MACMEOW_ALLOW_ADHOC=1` 發佈未公證的 ad-hoc 版本（行為見 `release.sh` 中 `adhoc_release` 的呼叫處）。只在無法公證時使用（CI 不使用）；舊版 App 的一鍵更新會拒絕 ad-hoc 版本，使用者需手動下載。
- `build`：從 tag 以 `git archive` 建置（未提交的檔案不會進入產物），並驗證 dmg 與 App（檢查項目見 `release.sh` 的 `verify_dmg`）。跨檔約定：
  - App 須符合 `common.sh` 的 `MACMEOW_REQUIREMENT`（一鍵更新）。
  - App 須含可執行的 `Contents/Resources/scripts/uninstall.sh`（cask 依賴，見 [homebrew.md](homebrew.md#安裝與移除)）。
  - `release-notes.md` 必須附上 `patches/SOURCES.md` 的 LGPL 原始碼清單（Release 內附修補版 Wine DLL；清單格式約定見 [wine-patches.md](wine-patches.md#新增修補)，找不到清單時 `build` 中止）；其餘內容見 `cmd_build`。
- `publish`：push main 與 tag（見 `cmd_publish`）。push tag 後由 CI 執行 `ci`（見 [ci.md](ci.md#發佈-workflow)）。
- `ci`（只在 CI 執行；檢查與步驟見 `cmd_ci`）：不經人工審核草稿，push tag 即正式發佈。`tap` 在 Release 公開後才執行，失敗時 CI 標為失敗但 Release 已發佈。
- `draft`：以 `dist/release/X.Y.Z/` 的產物建立 GitHub Release 草稿；CI 無法使用時可在本機 `build` 後執行（需 `gh auth login`）。
- `release`：驗證草稿附件後正式發佈並標為 Latest（見 `cmd_release`）；CI 無法使用時可在本機 `draft` 後執行。repo 首頁的 Releases 區塊與 README 的下載連結（`releases/latest`）即指向此版。
- `tap`：見 [homebrew.md](homebrew.md#發佈到-tap)。

已發佈的 App 一鍵更新時依賴發佈產物的約定，見 [scripts.md](scripts.md#updatesh)。

## 冒煙測試

冒煙測試需在 Terminal.app 或 Finder 由人執行（原因見 [AGENTS.md](../AGENTS.md#runtime-pitfalls)「Runtime pitfalls」），或在回報中寫明未執行。CI 會直接正式發佈，所以 `publish` 前必須以本機 `build` 的產物完整測試；發佈後可再以 `gh release download vX.Y.Z --pattern '*.dmg' -D <暫存資料夾>` 下載正式附件重做第 1 步。

1. 模擬使用者下載安裝：
   1. 結束 Cyder 的 Wine 程序後，把 dmg 複製到暫存資料夾，加上 quarantine 模擬下載：`xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" MacMeow-X.Y.Z.dmg`。
   2. 雙擊 dmg：視窗應顯示背景圖，`MacMeow.app` 與「應用程式」捷徑位於貓掌足跡兩端。
   3. 把 App 拖到「應用程式」後開啟：Gatekeeper 應只出現「從網際網路下載」的確認，不能出現「無法驗證開發者」或「Apple 無法檢查」。
2. `bash scripts/play.sh status` 的結果符合 [AGENTS.md](../AGENTS.md#runtime-pitfalls)「Runtime pitfalls」的啟動流程檢查（HostShield 監聽與登入器執行中）。
3. 按「開始遊戲」，進入遊戲並登入角色。
4. 若本版改了修補或外部狀態：`bash scripts/uninstall.sh` 後各 `check` 回報未修補，再以 App 重新套用一次。

## 失敗時

- 測試失敗且尚未 push：`git tag -d vX.Y.Z && git reset --hard HEAD~1` 撤回「chore(release): X.Y.Z」，修正並 commit 後從 `prepare` 重來。
- 已 push：修正後改發下一個 patch 版本（已發佈的壞版本可在說明中標註或刪除）。
- CI 失敗但產物沒問題（例如 Secret 設錯）：修正後在 Actions 頁面 Re-run；若停在草稿，`draft` 會覆蓋同一個草稿，`release` 再正式發佈。
- 只有 `tap` 失敗（Release 已發佈）：修正後在本機執行 `just release tap X.Y.Z`。
