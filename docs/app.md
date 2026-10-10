# MacMeow.app

`MacMeow.app`（SwiftUI，macOS 13+）的原始碼分層、擴充方式、各功能的行為，以及 App 與 dmg 的建置。

所有會改變遊戲、Cyder 或系統狀態的動作都呼叫打包的 `scripts/`（見 [scripts.md](scripts.md)）；不經腳本的只有：查詢最新版本、開啟 Cyder、啟用登入器程序、把 App 移到垃圾桶。建置與測試指令見 [development.md](development.md#建置與測試)，簽章見 [signing.md](signing.md)。

## 原始碼分層

`app/Sources/` 依層分資料夾；建置腳本以 `tools/lib.sh` 的 `app_sources` 收集整個資料夾，新增檔案不需要登記。

- `Core/`：純資料與規則（設定、porcelain 狀態、進度標記、首頁清單與摘要、Release、Issue 網址）。
- `Services/`：副作用（路徑、執行程序、記錄、設定檔、狀態輪詢、GitHub API、對話框與剪貼簿）。
- `Features/`：流程（啟動／關閉／迴路位址／遊戲資料夾、解除安裝、更新、回報問題、首頁狀態）；View 從這裡取得狀態並呼叫動作。
- `App/`：App 進入點、唯一的組合根 `AppModel`、選單與選單列。
- `UI/`：SwiftUI View 與共用元件。

## 擴充 App

- 新狀態：加到 `play.sh` 的 `porcelain()`，並同步 `Core/EnvStatus.swift`。
- 新進度：在腳本呼叫 `progress <id> <訊息>`（`common.sh`），並在 `Core/EnvStatus.swift` 的 `Step(progressID:)` 對應到清單項目。`@@STEP`／`@@PROGRESS`／`@@WAIT` 標記只在 `Core/ScriptEvent.swift` 解析。
- 新的腳本呼叫：加在 `Services/Scripts.swift`。
- 新的使用者腳本：加進 `app/build-app.sh` 的打包清單（`lib/*.sh` 會自動打包）。
- 新設定：加到 `common.sh` 的 `MACMEOW_SETTINGS` 與 `Core/AppConfig.swift`（見 [settings.md](settings.md#來源與優先序)）。

## 功能

- 互斥：`Core/LaunchPhase.swift` 的 `Operation` 列出的流程同一時間只執行一個（含流程中的對話框）；進行中不能更新，腳本執行中結束 App 會先確認。
- 啟動：依 `LaunchController.launch()` 的順序檢查並引導（迴路位址以 `Scripts.installLoopback` 經 osascript 取得管理員權限設定），最後以 `Scripts.play` 執行 `play.sh`。
- 視窗與選單列：關閉鈕只隱藏主視窗並移除 Dock 圖示，App 留在選單列（見 `UI/Window/MainWindow.swift`）；選單列項目見 `App/AppCommands.swift` 的 `MenuBarContent`。
- 「遊戲設定」卡：項目見 `Core/AppConfig.swift` 的 `GameSettings`；存檔與環境變數見 [settings.md](settings.md)。
- 回報問題（`Features/BugReporter.swift`）：預先填好 GitHub issue 表單，沒有後端；改 `.github/ISSUE_TEMPLATE/bug_report.yml` 的欄位 id 時同步改 `Core/IssueDraft.swift`。
- 更新（`Features/Updater.swift`）：檢查 GitHub 最新正式版，一鍵更新交給 `update.sh`；附件命名等與發佈的約定見 [scripts.md](scripts.md#updatesh)。Homebrew 安裝時的行為見 [homebrew.md](homebrew.md#安裝與移除)。
- 解除安裝（`Features/Uninstaller.swift`；腳本端見 [scripts.md](scripts.md#uninstallsh)）：`~/.Trash` 受隱私權保護，App 移到垃圾桶後不能從那裡執行腳本，所以先以 `uninstall.sh stage` 把 `purge` 複製到暫存資料夾，App 結束後才刪除設定。

## 建置與 dmg

- `app/build-app.sh`：建置 App 與 dmg；用法、產物與簽章選項見腳本開頭。
- dmg 背景（`app/make-dmg-background.swift`）與 Finder 排版的座標必須一致（兩端註解）。
- dmg 視窗版面由 Finder 排版（`layout_dmg`），需要 Aqua 工作階段與「自動化」權限；失敗時只警告並產生預設版面，`release.sh` 的 `verify_dmg` 會因缺少 `.DS_Store` 而失敗。
- dmg 結構是 `release.sh` 的 `verify_dmg` 與 `update.sh` 的約定，改動時一起改（內容見 `build-app.sh` 的 dmg 段註解）。
