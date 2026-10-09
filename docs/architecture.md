# 架構

## 執行鏈與連線路徑

```
認證器.exe (VB6) ──► HostShield.exe ×4（監聽 127.x.x.1:37601-37630 → WebSocket 通道到伺服器）
              └──► 貓貓TMS登入器.exe ──► MapleStory.exe（+ BlackCipher/NGS、NxOverlay）

MapleStory.exe → 202.80.104.28:37629（lo0 alias）
              → 登入器 0.0.0.0:37629（轉發）
              → 127.145.37.1:37629（HostShield）
              → WebSocket → 伺服器
```

- 執行環境：Cyder（CrossOver 26.3 / Wine 11.0，x86_64 經 Rosetta 2）。
- `MapleStory.exe` 是 PE32+ x86-64，與台服官方相同。

## 檔案職責

使用者流程（只能用 macOS 內建指令）：

- `scripts/lib/common.sh`：所有使用者腳本共用的路徑、常數（遊戲檔案、HostShield 與迴路位址）與函式（`wine_running`、`wineserver_kill` 等）。
- `scripts/play.sh`：入口。依序檢查前置條件、處理前次殘留程序、套用 loopback 與 DLL 修補、`vb6run`、Cyder 設定（`wineLocale=zh_TW`、`graphicsBackend=dxmt`、`msync`），再以 `open -a Cyder` 開 `認證器.exe`，等待 4 個 HostShield 位址都在監聽，最後啟動 `session.sh start`（登入器已在執行時也會補啟動）。`play.sh status` 顯示狀態，`status --porcelain` 輸出給 App 讀的 `key=value`，`stop` 關閉 shared bottle 內所有 Windows 程式。設 `MACMEOW_PROGRESS=1` 時各步驟訊息改為 `@@STEP <id> <訊息>`。
- `scripts/setup-loopback.sh install|uninstall|status`：lo0 alias 與 LaunchDaemon `tw.macmeow.loopback`。位址清單是 `common.sh` 的 `LOOPBACK_IPS`。唯一需要 root 的步驟。
- `scripts/patch-cyder-loopback.sh check|apply|restore`：wineserver 1 byte 修補；指令序列找不到或不唯一就不修改。
- `scripts/patch-cyder-dlls.sh check|apply|restore`：以 `patches/bin` 的 DLL 取代 engine 內建版；先比對 `SHA256SUMS`，只套用到 CrossOver 基底 26.3.0。
- `scripts/patch-cyder-winemac.sh check|apply|restore`（實驗性，只在 `HIDE_LAUNCHER_DOCK=1` 時由 `play.sh` 套用；未設定且 Wine 沒在執行時 `play.sh` 會還原）：改 engine `winemac.so` 兩段指令，讓設了 `CaptureDisplaysForFullscreen=y` 的程式成為沒有 Dock 圖示的輔助程式（[technical-notes.md](technical-notes.md) #10）。只套用到 SHA-256 已知的 `winemac.so`；其他版本 `apply` 回傳 2、不修改。
- `scripts/launcher-dock.sh status|hide|show`：在 shared bottle 登錄寫入或刪除 `AppDefaults\貓貓TMS登入器.exe\Mac Driver\CaptureDisplaysForFullscreen=y`（以 Wine 的 `reg.exe`；`status` 直接讀 `user.reg`）。
- `scripts/session.sh start|watch|close|status|cleanup`：遊戲階段監看（[technical-notes.md](technical-notes.md) #11）。`start` 以 `nohup` 在背景執行 `watch`，PID 記在 `session-watch.pid`，記錄寫到 `session.log`；同時只有一個，wineserver PID 改變（Wine 結束）就退出。本專案程式的判斷在 `common.sh` 的 `session_procs`。
- `scripts/update.sh prepare <X.Y.Z> <目前的 .app>|install <目前的 .app> <PID>`：App 一鍵更新。`prepare` 在 App 執行中先檢查目前 App 可原地取代（不在 App Translocation、App 與上層資料夾可寫入），以版本號組成網址 `https://github.com/$MACMEOW_REPO/releases/download/vX.Y.Z/MacMeow-X.Y.Z.dmg`（不接受外部傳入網址），以 `curl --proto '=https' --proto-redir '=https' -C -` 續傳下載 dmg（進度轉成 `@@PROGRESS <百分比>`）與同名 `.sha256` 並比對（同一來源，只確認完整；不符時刪除重下一次）；連不上、中斷或 30 秒內低於 1 KB/s 時輸出 `@@WAIT`，10 秒後從中斷處繼續，連續 30 次沒有進展才放棄，4xx（408、429 除外）與轉址到非 https 不重試；未完成的 dmg 保留，下次 `prepare` 接著下載。以 `dmg_attach` 唯讀掛載後 `ditto` 取出 `MacMeow.app` 到 `~/Library/Caches/MacMeow/update/`，以 `codesign --verify --deep --strict -R="$MACMEOW_REQUIREMENT"` 驗證簽章來源（`common.sh`：Apple 簽發的 Developer ID Application 憑證、官方 Team ID `MACMEOW_TEAM_ID`、bundle id；與目前 App 的簽章無關，自行建置的 ad-hoc 版也只接受官方版）與版本。`install` 把輸出寫到 `update.log`，等 PID 結束（最多 60 秒，逾時放棄），先把新版 `ditto` 到同一資料夾的 `.MacMeow.app.macmeow-new`，再把舊版改名為 `.macmeow-old`、新版改名為原路徑，失敗時改回舊版；最後刪除暫存並 `open` App。整個腳本以 `{ …; exit; }` 包住，取代所在 App 時 bash 不會再讀到新檔案。依賴 `release.sh` 的 tag 與附件命名（`vX.Y.Z`、`MacMeow-X.Y.Z.dmg`、`.dmg.sha256`）、dmg 內的 `MacMeow.app` 與簽章需求；`release.sh` 的 `verify_dmg` 會檢查 App 符合 `MACMEOW_REQUIREMENT`。
- `scripts/report.sh [log <記錄檔> [行數]|bundle <輸出.zip> [記錄檔]]`：問題回報用的診斷資訊。預設輸出環境摘要（Markdown：App／macOS／Cyder／engine 版本、Cyder 設定、`MapleStory.exe` 大小與雜湊前綴、修補 `check`、`status --porcelain`）；`bundle` 以 `ditto` 打包摘要、`play.sh status`、記錄檔最後 5000 行與 7 天內的 MacMeow 當機報告。所有輸出經 `redact()` 隱藏家目錄、`/Users/<名稱>`、使用者名稱（3 字元以上）與 HostShield 程序參數中的 token；不讀取 `login.txt`。App 以 `MACMEOW_VERSION` 傳入版本。
- `scripts/uninstall.sh`：還原以下「外部狀態」中所有可還原項目。

App（SwiftUI；建置需要 Xcode 或 Command Line Tools，執行時只用系統 framework）：

- `app/Sources/*.swift`：`MacMeow.app` 主程式（SwiftUI，macOS 13+）。只做 UI 與引導，所有動作都呼叫打包的腳本（查詢最新版本除外）：
  - 狀態：每 3 秒執行 `play.sh status --porcelain`（`key=value`，key 定義在 `play.sh` 的 `porcelain()`，對應 `app/Sources/Status.swift`）。
  - 啟動：依序檢查 Cyder、遊戲資料夾（`NSOpenPanel`，以 porcelain 驗證）、Cyder 初始化（開啟 Cyder 等待 prefix）、迴路位址（`osascript … with administrator privileges` 執行 `setup-loopback.sh install`），再以 `MACMEOW_PROGRESS=1` 執行 `play.sh`，解析 `@@STEP <id> <訊息>`（`common.sh` 的 `progress`）顯示進度。
  - 全部關閉：確認後執行 `play.sh stop`。
  - 顯示登入器：以 porcelain 的 `launcher_pid` 啟用登入器程序（`NSRunningApplication.activate`）；Wine 會還原縮到最小的視窗。
  - 視窗與選單列（`MacMeowApp.swift`）：主視窗的關閉鈕改為隱藏（`MainWindow` 把關閉鈕的 action 換成自己的 `hide:`：`orderOut` 並把 activation policy 改為 `.accessory`，Dock 不顯示圖示；⌘W 的 `performClose:` 也經過關閉鈕），叫回時改回 `.regular`；最後一個視窗關閉時不結束 App，隱藏中從 Finder 再開啟也會叫回主視窗；`MenuBarExtra` 貓掌圖示提供狀態、顯示主視窗、開始遊戲／全部關閉與結束。
  - 「Wine 設定」卡：同步機制、遊戲關閉時自動收尾，存在 config 並以環境變數傳給 `play.sh`。
  - 回報問題（`BugReport.swift`）：sheet 表單，以 `report.sh` 與 `report.sh log` 取得預覽內容；送出時以 `report.sh bundle` 在 `~/Library/Logs/MacMeow/reports/` 產生診斷檔並在 Finder 選取，再開啟 `issues/new?template=bug_report.yml&<欄位 id>=…` 預先填好 `.github/ISSUE_TEMPLATE/bug_report.yml` 的欄位（網址超過 7000 字元時先刪減記錄再截短文字）。沒有後端；改欄位 id 時兩邊一起改。
  - 更新（`Updater.swift`）：以 `URLSession` 讀取 GitHub API `repos/xlanstar/mac-meow/releases/latest`（只回傳正式版，不含草稿與預先發行版），把 `tag_name` 去掉 `v` 後與 `CFBundleShortVersionString` 以 `.numeric` 比較（開發版 `dev` 不提示）；還沒有 `MacMeow-X.Y.Z.dmg` 附件時視為檢查失敗（稍後再試）。「自動檢查更新」開啟時（預設）App 啟動後立即檢查，之後每 24 小時一次，失敗時不提示、10 分鐘後再試；有新版時主視窗頂端顯示橫幅、選單列加上「更新到 X.Y.Z」，「略過」的版本不再自動提醒；App 選單「檢查更新⋯」一律以對話框回報。「更新」執行 `update.sh prepare <版本> <App 路徑>`（顯示 `@@PROGRESS` 下載進度，`@@WAIT` 時顯示「等待網路」），成功後以 `Shell.spawn` 啟動 `update.sh install <App 路徑> <PID>`（不讀取輸出，App 結束後繼續執行）並結束 App；失敗時顯示最後一行錯誤並提供 Release 頁面手動下載。啟動流程進行中不更新。
- `app/make-icon.swift`：以 Core Graphics 繪製 App 圖示，建置時轉成 `AppIcon.icns`。
- `app/make-dmg-background.swift`：繪製 dmg 視窗背景（1x／2x，`tiffutil` 合成 `background.tiff`）。版面座標與 `build-app.sh` 中 Finder 排版的視窗大小、圖示位置必須一致。
- dmg 內容：卷宗「貓貓谷 for Mac」，含 `MacMeow.app`、指向 `/Applications` 的捷徑「應用程式」、`.background/background.tiff`、`.VolumeIcon.icns` 與 Finder 寫入的 `.DS_Store`（視窗大小、背景、圖示位置）。
- `app/build-app.sh`：以 `swiftc` 編譯 `app/Sources` 與圖示（中間檔在 `build/app/`），產生 `dist/MacMeow.app` 與可拖曳安裝的 `dist/MacMeow-<版本>.dmg`（預設 ad-hoc 簽章），把 `scripts/` 使用者腳本（含 `lib/`）與 `patches/bin`（含 `SHA256SUMS`）放進 `Contents/Resources`。

所有修改 engine 的 `apply`／`restore` 在 Cyder 的 Wine 執行中都會拒絕。`restore` 只在目前檔案仍是本專案修補版時才寫回備份；engine 已被 Cyder 更新時只刪除過期備份，避免把舊檔蓋回新 engine。

開發用（見 [development.md](development.md)）：

- `tools/*.sh`：啟動、診斷、自動化、DLL 重建、發佈（`release.sh`）；共用函式在 `tools/lib.sh`。
- `tools/src/<name>/`：診斷工具原始碼，以 `tools/build.sh` 建置到 `build/tools/`。
- `patches/*.patch`：Wine 原始碼修補；`patches/bin/`：預先建置的 DLL 與 `SHA256SUMS`。

## 外部狀態

格式：位置：變更內容 → 還原方式。

- Cyder engine `~/.cyder/runtime/Engines/wine-x86_64`：wineserver 與 DLL 被修補，開發時 `bin/wine` 可能被重新簽章；原檔備份為 `*.macmeow-orig`，DLL 另有 `*.macmeow-applied` 標記 → `patch-cyder-*.sh restore`、`tools/sign-debug.sh restore`（還原後刪除備份）。
- Cyder bottle `~/Library/Application Support/Cyder/bottles/shared`：安裝 `vb6run` → 保留。
- Cyder engine `lib/wine/x86_64-unix/winemac.so`：兩段指令被修補並重新 ad-hoc 簽章；原檔備份為 `winemac.so.macmeow-orig` → `patch-cyder-winemac.sh restore`。
- Cyder shared bottle 登錄（`user.reg`）：`HKCU\Software\Wine\AppDefaults\貓貓TMS登入器.exe\Mac Driver` 的 `CaptureDisplaysForFullscreen="y"` → `launcher-dock.sh show`（`uninstall.sh` 呼叫；`HIDE_LAUNCHER_DOCK` 不是 `1` 時 `play.sh` 也會呼叫）。
- Cyder 的程序：`session.sh` 在 Wine 結束後結束 Cyder 遺留的 `CyderSwift --sentinel-connect`（只限 `--fifo` 已刪除或 PPID 為 1 者）→ 不需還原。
- Cyder `settings.json`：`wineLocale`、`graphicsBackend`、`msync`、`esync` → 保留，`uninstall.sh` 提示使用者自行調整。
- lo0 alias 與 `/Library/LaunchDaemons/tw.macmeow.loopback.plist` → `setup-loopback.sh uninstall`。
- `~/Library/Application Support/MacMeow/config`（`GAME_DIR=`、`MAPLE_SYNC=`、`AUTO_CLOSE=`）與 `session-watch.pid`、`~/Library/Logs/MacMeow/`（`launcher.log`、`session.log`、`update.log`、回報診斷檔 `reports/`）、`~/Library/Caches/MacMeow/`（`update.sh` 暫存的新版）、App 偏好設定 `tw.macmeow.launcher`（SwiftUI 視窗位置、`autoCheckUpdates`、`skippedUpdateVersion`）與 `~/Library/Saved Application State/tw.macmeow.launcher.savedState` → `uninstall.sh` 刪除。

## 環境變數

- `GAME_DIR`（預設 `~/Games/MapleStory`）：遊戲資料夾，需含 `MapleStory.exe`、`認證器.exe`、`貓貓TMS登入器.exe`、`HostShield.exe`、`XCGUI.dll`。
- `CYDER_ENGINE`（預設 `~/.cyder/runtime/Engines/wine-x86_64`）：Cyder engine 路徑。
- `MAPLE_SYNC`（預設 `msync`，可為 `none|msync|esync`）：寫入 Cyder 設定的同步模式。
- `AUTO_CLOSE`（預設 `1`）：`0` 時 `play.sh` 不啟動 `session.sh`，遊戲關閉後不自動收尾。
- `HIDE_LAUNCHER_DOCK`（預設 `0`，實驗性）：`1` 時 `play.sh` 套用 winemac 修補並執行 `launcher-dock.sh hide`，否則執行 `show` 並還原 winemac 修補。開啟後遊戲會與登入伺服器斷線（[technical-notes.md](technical-notes.md) #10），App 不提供這個選項。

## 外部變動時要更新的地方

- 私服更換連線位址：更新 `scripts/lib/common.sh` 的 `HOSTSHIELD_IPS`／`GAME_ALIAS_IP`；使用者需重新執行 `setup-loopback.sh install`。
- Cyder engine 的 CrossOver 基底改變：`patch-cyder-dlls.sh` 會拒絕套用。以新基底重建 DLL，並更新 `REQUIRED_BASE`、`patches/SOURCES.md`、`patches/bin/SHA256SUMS`。
- Cyder engine 的 `winemac.so` 改變（任何 engine 更新都可能）：`patch-cyder-winemac.sh` 不修改，登入器照常顯示在 Dock。以 `otool -tV` 找出新版 `transformProcessToForeground:` 的對應指令，重新計算 `KNOWN_SHA256`、偏移與 RIP 相對位移（[technical-notes.md](technical-notes.md) #10）。
- Repo 改名或搬移：更新 `scripts/lib/common.sh` 的 `MACMEOW_REPO` 與 `app/Sources/Paths.swift` 的 `repo`、`knownIssues`、`latestRelease`；已發佈的舊版 App 仍查詢舊網址，仰賴 GitHub 的轉址。
- 發佈附件命名、dmg 內容、bundle id 或簽章 Team ID 改變：舊版 App 的 `update.sh` 會拒絕更新；改變前先讓 `update.sh` 支援新格式並發佈一版。換 Team ID 時更新 `common.sh` 的 `MACMEOW_TEAM_ID`，使用者需手動下載一次。
- 登入器改名：更新 `common.sh` 的 `LAUNCHER_EXE` 與 `launcher-dock.sh` 的 `REG_SECTION`（`user.reg` 以 `\x` 跳脫非 ASCII 字元）。
- 伺服器要求的 `MapleStory.exe` 版本改變：更新 `README.md` 系統需求。
- macOS 28 移除一般用途的 Rosetta 2：Apple 公告 macOS 27 是最後一個完整支援 Rosetta 的版本（macOS 26.4 起啟動 Intel 程式會跳出淘汰通知），macOS 28 起只保留給「仰賴 Intel 框架、已不再維護的舊遊戲」，是否涵蓋 Wine 未說明。整條執行鏈都依賴 Rosetta：Cyder engine 是 x86_64 Wine，`wineserver_kill` 以 `arch -x86_64` 執行，`patches/bin` 的 DLL 與 `patch-cyder-loopback.sh` 的指令序列也都針對 x86_64 engine。若 Cyder 改用原生 ARM64 Wine（CrossOver 已有 ARM64 預覽版，以 FEX 模擬 x86），上述修補都要重新驗證或重做。macOS 28 確認相容（或確認不支援）後，更新 `README.md` 已知問題與系統需求，以及 `docs/known-issues.md`。
