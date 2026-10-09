# 開發

## 環境

- Apple Silicon Mac、Rosetta 2、Cyder。
- Xcode 或 Command Line Tools（`swiftc`、`/usr/bin/clang`、`iconutil`）：建置 `MacMeow.app` 與 `tools/src/` 的 macOS 工具。
- `brew install llvm lld bison`：只有重建 Wine DLL 與 Windows 端工具時需要。

## 目錄分工

- `scripts/`：使用者流程，會打包進 `MacMeow.app`，只能用 macOS 內建指令。共用路徑、常數與函式在 `scripts/lib/common.sh`（遊戲檔案清單、迴路位址、Cyder 路徑、`wine_running`、`wineserver_kill` 等），新增腳本請 source 它，不要重複定義。
- `app/`：SwiftUI App（`app/Sources/`，Swift 5 語言模式、最低 macOS 13），由 `app/build-app.sh` 以 `swiftc` 編譯，不需要 Xcode 專案。App 只負責 UI：需要新狀態就加到 `play.sh` 的 `porcelain()` 並同步 `app/Sources/Status.swift`；需要新進度就在腳本呼叫 `progress <id> <訊息>`，並在 `Step.fromProgress` 對應清單項目。
- `tools/`：開發與診斷，可用 Xcode、Homebrew、`python3`。入口腳本放在 `tools/*.sh`，共用函式在 `tools/lib.sh`（建立在 `common.sh` 之上），原始碼在 `tools/src/<工具>/`，建置產物一律輸出到 `build/tools/`，診斷紀錄一律寫到 `debug/`。
- 例外：`tools/sign-debug.sh` 會被 `scripts/uninstall.sh` 呼叫，因此只用 macOS 內建指令。

## 建置與測試

```sh
bash app/build-app.sh                              # dist/MacMeow.app 與 dmg（預設 ad-hoc 簽章；需允許終端機控制 Finder）
open dist/MacMeow.app                              # 開啟 App；記錄在 ~/Library/Logs/MacMeow/launcher.log
bash scripts/play.sh status --porcelain            # App 讀取的狀態（key=value）
GAME_DIR=~/Games/MapleStory bash scripts/play.sh   # 直接跑使用者流程
bash scripts/play.sh status                        # 通道／程序狀態
bash scripts/patch-cyder-dlls.sh check             # 各修補也都有 check
bash scripts/session.sh status                     # 遊戲階段監看；記錄在 ~/Library/Logs/MacMeow/session.log
lsappinfo list | grep -A4 '"wine"'                 # 登入器應為 type="UIElement"（不在 Dock），遊戲為 "Foreground"
```

## 提交前檢查（prek）

```sh
brew install prek
prek install            # 安裝 pre-commit 與 commit-msg hook
prek run -a             # 對所有檔案執行
prek update             # 更新 hook 版本（改寫 prek.toml 的 rev）
```

設定在 `prek.toml`；各工具的設定檔：`.editorconfig`（shfmt）、`.shellcheckrc`、`.swift-format`（工具鏈內建的 `swift format`）、`ruff.toml`、`_typos.toml`、`committed.toml`（commit 訊息格式）。除了 AGENTS.md 的 Hard rules（遊戲檔、`login.txt`、`.env`）、bash 3.2 相容與 `patches/bin/SHA256SUMS`，也檢查 commit 訊息必須有 body（`tools/check-commit-body.sh`）。shfmt、`swift format`、ruff 會直接改寫檔案，改完重新 `git add` 再提交。

## 重建 Wine DLL

```sh
bash tools/build-wine-dlls.sh
(cd patches/bin/x86_64-windows && shasum -a 256 *.dll) > patches/bin/SHA256SUMS
```

腳本會下載 CrossOver 26.3.0 原始碼（校驗 SHA-256）到 `build/`、套用 `patches/*.patch`，只建置 `wsock32.dll`、`advapi32.dll`，strip 後覆寫 `patches/bin/x86_64-windows/`。

新增 Wine 修補：

1. 在 `build/src/sources/wine` 修改。
2. 以 `diff -u` 產生 `a/`、`b/` 前綴的 patch 放進 `patches/`。
3. 在 `tools/build-wine-dlls.sh` 的 `MODULES` 加入對應模組。
4. 更新 `patches/SOURCES.md`，根因寫進 [technical-notes.md](technical-notes.md)。

## 診斷工具

`bash tools/build.sh [目標...]` 建置到 `build/tools/`（不指定則全部；`wgui.exe`、`recvcheck.exe` 需要先跑過 `build-wine-dlls.sh`）。入口腳本缺工具時會自動建置。各腳本開頭有完整用法。

啟動與操作（GUI 類 Wine 程式需在 Terminal.app 內執行）：

- `tools/run-game.sh [plain|trace|relay|virtual|server]`：不經 Cyder.app 直接以 engine 啟動完整流程。`plain` 無 trace（效能比較）；其餘模式只對 `MapleStory.exe` 開 Wine 頻道並記錄執行緒數與 socket。`SYNC`、`GFX`、`WZCACHE`、`HUD=1`（Metal FPS HUD）、`WINEDEBUG`、`EXTRA_DEBUG`、`EXTRA_ENV` 可切換。
- `tools/wgui.sh list|click|sclick|shot|fg|key`：在 bottle 內列出 Wine 視窗、點擊、按鍵、截圖。預設經 Terminal.app 執行並取回輸出，已在 Terminal.app 內可加 `--here`。
- `tools/auto-start.sh`：等登入器視窗出現後以 `SendInput` 點「開始遊戲」，直到 `MapleStory.exe` 啟動。
- `tools/shot-game.sh [輸出檔] [視窗標題]`：擷取遊戲視窗（被遮住也可，螢幕鎖定時不行）。

堆疊與效能：

- `tools/sign-debug.sh status|apply|restore`：替 engine 的 `wine` 加 `get-task-allow`（machstack／LLDB 需要），用完執行 `restore`。
- `tools/stack.sh mach|prof|lldb|sample`：擷取執行中 `MapleStory.exe` 的堆疊。`mach` 以 Mach API 讀 Rosetta 執行緒的原生／x86 狀態並解析符號；`prof` 多次快照統計 CPU 與呼叫鏈；`lldb` 附加後擷取原生堆疊；`sample` 為 macOS `sample`。
- `build/tools/callchain`、`memdump`、`tools/src/machstack/pesym.py`：呼叫鏈取樣、讀記憶體字串、Wine PE 位址轉函式名。

重現與驗證：

- `smctest`、`smctest2`、`smctest3`：Rosetta 同頁寫入（SMC）成本。
- `wthreads.exe`、`reloadtest.exe`、`recvcheck.exe`：Wine 執行緒狀態、rsaenh 重載、recv 修補。在 bottle 內執行：`bash -c 'source tools/lib.sh && run_wine build/tools/wthreads.exe <pid-hex>'`。

## Rosetta 除錯要點

- `sample`／`spindump` 會在 CoreSymbolication 內崩潰；程序凍結時 LLDB 無法暫停。改用 `tools/stack.sh mach`（machstack：`task_for_pid` + `thread_get_state`）。
- Rosetta 執行緒在系統呼叫中時，`[sp+8]` 起依序是 x86 `rip(arm 返回位址), rax, rcx, rdx, rbx, rsp, rbp, rsi, rdi, r8–r15, rflags`；執行翻譯碼時 `x4=rsp`、`x5=rbp`。
- LLDB（含 watchpoint）可附加執行中的 Rosetta 程序並取得精確 x86 `rip`，但不認得 Wine PE 映像；用 `pesym.py` 對照位址。
- `WINEDEBUG` 可用 `程序名.exe:+channel` 只對單一程序開啟。

## 發佈

### 版本號

`VERSION` 採 SemVer `X.Y.Z`，tag 為 `vX.Y.Z`。1.0 之前：

- `Z`（patch）：修正，使用者不需要做任何事。
- `Y`（minor）：新功能、支援新的 Cyder engine／CrossOver 基底（重建 DLL）、私服位址變更（使用者需重新授權網路設定）、外部狀態的種類有變。
- 使用者需要手動處理的變更，在 CHANGELOG 該項目寫清楚要做什麼。

### 簽章與公證

`app/build-app.sh` 預設只做 ad-hoc 簽章：本機建置的 App 沒有 quarantine 標記，自己用沒問題；但從網路下載的 ad-hoc App 會被 Gatekeeper 擋下，所以發佈版本必須用 Developer ID 簽章並送 Apple 公證。

一次性設定（需 Apple Developer Program 帳號）：

1. 建立 **Developer ID Application** 憑證（只有帳號持有人能建立；`Apple Development` 憑證不能用於發佈）。Xcode → Settings → Accounts → Manage Certificates → `+`；Xcode 無法建立時改用網站：以 `openssl req -new -newkey rsa:2048 -nodes -keyout devid.key -out devid.csr -subj "/CN=MacMeow Developer ID"` 產生 CSR，到 [Certificates](https://developer.apple.com/account/resources/certificates/add) 選 Developer ID Application（G2 Sub-CA）上傳，下載 `.cer` 後與私鑰合成 `.p12`（`/usr/bin/openssl pkcs12 -export`）再 `security import` 到登入鑰匙圈，最後刪除私鑰檔。確認：`security find-identity -v -p codesigning`。
2. 在 [appleid.apple.com](https://appleid.apple.com) 建立 App 專用密碼，存成 notarytool profile：
   ```sh
   xcrun notarytool store-credentials macmeow-notary --apple-id <Apple ID> --team-id <Team ID> --password <App 專用密碼>
   ```
3. `cp .env.example .env`，填入兩個值（`.env` 已列入 `.gitignore`，不提交）：
   ```sh
   MACMEOW_SIGN_ID=<SHA-1>                # security find-identity -v -p codesigning；也可填完整憑證名稱
   MACMEOW_NOTARY_PROFILE=macmeow-notary
   ```
   （`MACMEOW_NOTARY_KEYCHAIN` 選用：profile 不在預設鑰匙圈時指定路徑，CI 使用。）
   `app/build-app.sh` 與 `tools/release.sh` 啟動時以 `tools/lib.sh` 的 `load_env` 載入 `.env`；已存在的環境變數優先，例如 `MACMEOW_NOTARY_PROFILE= bash app/build-app.sh` 只簽章不公證。

| 設定（環境變數或 `.env`） | `build-app.sh` 的行為 |
|---|---|
| 都未設定 | ad-hoc 簽章 |
| `MACMEOW_SIGN_ID` | Hardened Runtime + 安全時間戳記簽章，不公證 |
| 兩者都設定 | 上述簽章後，以 `notarytool submit --wait` 公證 App（暫時 zip），`stapler staple` 把票證釘進 App 後才打包 dmg；dmg 再以同一憑證簽章、公證並 `stapler staple`（共公證兩次，App 與 dmg 離線都能通過 Gatekeeper） |

App 本身只有一個 Mach-O，`scripts/` 與 Windows DLL 是資源檔，由 bundle 簽章封存；Hardened Runtime 不需要額外 entitlement（App 只以 `Process` 呼叫系統的 `/bin/bash`、`osascript`）。公證失敗時 `build-app.sh` 會印出 `xcrun notarytool log <id>` 指令查看原因。

### 流程

由 `tools/release.sh` 與 GitHub Actions（`.github/workflows/release.yml`）執行，每一步都可以單獨重跑：

```sh
bash tools/release.sh check   X.Y.Z   # 只檢查，不修改
bash tools/release.sh prepare X.Y.Z   # 改 CHANGELOG／VERSION，commit「chore(release): X.Y.Z」+ tag vX.Y.Z（不 push）
bash tools/release.sh build   X.Y.Z   # 本機從 tag 建置 → dist/release/X.Y.Z/，push 前必須冒煙測試
bash tools/release.sh publish X.Y.Z   # push main + tag → CI 建置、簽章、公證並正式發佈（Latest）
gh run watch                          # 等 CI 完成
```

- `check`：在 `main`、工作目錄乾淨、版本號大於 `VERSION`、tag 不存在、`## Unreleased` 至少一項、所有 `*.sh` 通過 `bash -n`、`scripts/`／`app/` 通過 shellcheck（有安裝時）、`app/Sources` 通過 `swiftc -typecheck`、`patches/bin/SHA256SUMS` 與 DLL 相符、`MACMEOW_SIGN_ID` 是鑰匙圈中有效的 Developer ID Application 憑證且 `MACMEOW_NOTARY_PROFILE` 能登入。
  - 例外：`MACMEOW_ALLOW_ADHOC=1` 跳過簽章檢查，`build` 產生 ad-hoc 版本，release notes 改為教使用者到「系統設定 → 隱私權與安全性」按「仍要打開」。只在無法公證時使用（CI 不使用）。
- `prepare`：把 `## Unreleased` 下的項目移到 `## X.Y.Z — YYYY-MM-DD`，上方留一個空的 `## Unreleased`。
- `build`：以 `git archive vX.Y.Z` 取出原始碼到 `build/release/X.Y.Z/` 再執行 `app/build-app.sh`，所以未提交的檔案不會進入產物。驗證 dmg 的簽章、公證票證與 Gatekeeper 評估（`spctl --type open --context context:primary-signature`），再掛載 dmg 驗證內含「應用程式」捷徑與視窗版面（`.DS_Store`、背景圖），以及 App 的 `codesign`、`CFBundleShortVersionString`、公證票證（`stapler validate`）與 Gatekeeper 評估（`spctl` 須為 `Notarized Developer ID`），並產生：
  - `MacMeow-X.Y.Z.dmg`、`MacMeow-X.Y.Z.dmg.sha256`
  - `release-notes.md`：CHANGELOG 該版內容 + 安裝方式 + dmg 的 SHA-256 + `patches/SOURCES.md` 的 LGPL 原始碼表（Release 內附修補版 Wine DLL，必須附上）。
- `publish`：`git push --atomic origin main vX.Y.Z`。需要 `origin` remote。
- `ci`（只在 CI 執行）：確認 tag 的 `VERSION` 為 X.Y.Z、`CHANGELOG.md` 有 `## X.Y.Z` 段落、tag 在 `origin/main` 上，再執行 `build`、`draft` 與 `release`，push tag 即正式發佈，不經人工審核草稿。
- `draft`：以 `dist/release/X.Y.Z/` 的產物建立 GitHub Release 草稿；草稿已存在時覆蓋附件與說明，已正式發佈則拒絕。CI 無法使用時可在本機 `build` 後執行（需 `gh auth login`）。
- `release`：下載草稿的 dmg 與 `.sha256`，驗證 SHA-256、`codesign`、公證票證、Gatekeeper 與 App 版本後，以 `gh release edit --draft=false --latest` 正式發佈；CI 由 `ci` 呼叫，CI 無法使用時可在本機 `draft` 後執行。repo 首頁的 Releases 區塊與 README 的下載連結（`releases/latest`）即指向此版。已正式發佈時只印出網址。

### GitHub Actions

`.github/workflows/release.yml` 在 push `vX.Y.Z` tag 時於 `macos-15`（arm64）執行：`tools/ci-keychain.sh setup` 建立暫時鑰匙圈，匯入 Developer ID 憑證與 Developer ID G2 中繼憑證、存入 notarytool profile，並把 `MACMEOW_SIGN_ID`／`MACMEOW_NOTARY_PROFILE`／`MACMEOW_NOTARY_KEYCHAIN` 寫入 `$GITHUB_ENV`；接著 `release.sh ci`（建置、公證並正式發佈）；最後無論成敗都 `ci-keychain.sh cleanup` 刪除鑰匙圈。Swift 工具鏈以 runner 映像的 Xcode 為準，版本印在「工具版本」步驟。dmg 視窗版面由 `build-app.sh` 以 AppleScript 請 Finder 排版（需 Aqua 工作階段與「自動化」權限，GitHub 的 macOS runner 已具備）；Finder 90 秒內未完成時只警告並產生預設版面的 dmg，`release.sh` 的 dmg 驗證會因缺少 `.DS_Store` 而失敗。

Repo 的 Actions Secrets 需要以下項目。在已設定 GitHub `origin` 且 `gh auth login` 的終端機執行 `bash tools/setup-ci-secrets.sh` 即可一次設定：

| Secret | 內容 |
|---|---|
| `DEVELOPER_ID_P12_BASE64` | Developer ID Application 憑證＋私鑰的 `.p12`，以 `base64 -i <檔案>` 編碼 |
| `DEVELOPER_ID_P12_PASSWORD` | 該 `.p12` 的密碼 |
| `APPLE_ID` | 公證用 Apple ID |
| `APPLE_TEAM_ID` | Team ID（10 碼） |
| `APPLE_APP_PASSWORD` | 公證用 App 專用密碼（建議 CI 專用一組，方便撤銷） |

`tools/setup-ci-secrets.sh`：以 `security export` 匯出登入鑰匙圈的簽章身分（macOS 會要求輸入登入密碼允許匯出），只挑出 `MACMEOW_SIGN_ID` 指定的憑證與對應私鑰，以隨機密碼重新打包成 `.p12`；詢問 Apple ID 與 App 專用密碼並以 `notarytool history` 驗證；確認後以 `gh secret set` 寫入，Team ID 取自憑證。暫存檔結束時刪除，`.p12` 密碼不另外保存（需要時重跑即可）。`--dry-run` 只檢查匯出。憑證到期或更換、App 專用密碼撤銷時重跑一次。

### 冒煙測試

Agent shell 無法啟動 GUI Wine 程式；這一步需在 Terminal.app 或 Finder 由人執行，或在回報中寫明未執行。CI 會直接正式發佈，所以 `publish` 前必須以本機 `build` 的產物完整測試；發佈後可再以 `gh release download vX.Y.Z --pattern '*.dmg' -D <暫存資料夾>` 下載正式附件重做第 1 步。

1. 結束 Cyder 的 Wine 程序後，把 dmg 複製到暫存資料夾，加上 quarantine 模擬下載：`xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;" MacMeow-X.Y.Z.dmg`。雙擊 dmg：視窗應顯示背景圖，`MacMeow.app` 與「應用程式」捷徑位於貓掌足跡兩端；把 App 拖到「應用程式」後開啟：應只出現「從網際網路下載」的確認，不能出現「無法驗證開發者」或「Apple 無法檢查」。
2. `bash scripts/play.sh status`：4 個 HostShield 位址在 `37601-37630` 監聽，`貓貓TMS登入器.exe` 在執行。
3. 按「開始遊戲」，進入遊戲並登入角色。
4. 若本版改了修補或外部狀態：`bash scripts/uninstall.sh` 後各 `check` 回報未修補，再以 App 重新套用一次。

測試失敗且尚未 push：`git tag -d vX.Y.Z && git reset --hard HEAD~1` 撤回「chore(release): X.Y.Z」，修正並 commit 後從 `prepare` 重來。已 push：tag 不移動、不重用，修正後改發下一個 patch 版本（已發佈的壞版本可在說明中標註或刪除）。CI 失敗但產物沒問題（例如 Secret 設錯）：修正後在 Actions 頁面 Re-run；若停在草稿，`draft` 會覆蓋同一個草稿，`release` 再正式發佈。

### Repo 圖片

`bash tools/repo-images.sh [--update-readme] [App 視窗截圖.png]` 以 `tools/src/repo-images/` 的 HTML 範本與 App 視窗截圖（預設 `debug/app-shot.png`，⌘⇧4 → 空白鍵擷取）產生 2560×1280 JPEG 到 `build/repo-images/`。需先 `bash app/build-app.sh` 產生圖示，並安裝 Google Chrome。

| 圖片 | 範本 | 用途 |
|---|---|---|
| `social-preview.jpg` | `social-preview.html` | 連結卡片：大標語 + App 視窗。在 repo「Settings → General → Social preview」上傳（上限 1 MB），不放進 repo。 |
| `readme-hero-light.jpg`、`readme-hero-dark.jpg` | `readme-hero.html`（`?theme=dark` 為深色版） | README 頂部主圖：只有 App 視窗，以 `<picture>` 依 GitHub 淺色／深色模式切換。 |

App 介面改變後重新擷取截圖並執行 `--update-readme`，把 README 主圖複製到 `docs/images/` 後提交；社群預覽圖要另外到 Settings 重新上傳。
