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
- `scripts/play.sh`：入口。依序檢查前置條件、處理前次殘留程序、套用 loopback 修補與 DLL 修補、`vb6run`、Cyder 設定（`wineLocale=zh_TW`、`graphicsBackend=dxmt`、`msync`），再以 `open -a Cyder` 開 `認證器.exe` 並等待 4 個 HostShield 位址都在監聽。`play.sh status` 顯示狀態，`status --porcelain` 輸出給 App 讀的 `key=value`，`stop` 關閉 shared bottle 內所有 Windows 程式。設 `MACMEOW_PROGRESS=1` 時各步驟訊息改為 `@@STEP <id> <訊息>`。
- `scripts/setup-loopback.sh install|uninstall|status`：lo0 alias 與 LaunchDaemon `tw.macmeow.loopback`。位址清單是 `common.sh` 的 `LOOPBACK_IPS`。唯一需要 root 的步驟。
- `scripts/patch-cyder-loopback.sh check|apply|restore`：wineserver 1 byte 修補；指令序列找不到或不唯一就不修改。
- `scripts/patch-cyder-dlls.sh check|apply|restore`：以 `patches/bin` 的 DLL 取代 engine 內建版；先比對 `SHA256SUMS`，只套用到 CrossOver 基底 26.3.0。
- `scripts/uninstall.sh`：還原以下「外部狀態」中所有可還原項目。

App（SwiftUI；建置需要 Xcode 或 Command Line Tools，執行時只用系統 framework）：

- `app/Sources/*.swift`：`MacMeow.app` 主程式（SwiftUI，macOS 13+）。只做 UI 與引導，所有動作都呼叫打包的腳本：
  - 狀態：每 3 秒執行 `play.sh status --porcelain`（`key=value`，key 定義在 `play.sh` 的 `porcelain()`，對應 `app/Sources/Status.swift`）。
  - 啟動：依序檢查 Cyder、遊戲資料夾（`NSOpenPanel`，以 porcelain 驗證）、Cyder 初始化（開啟 Cyder 等待 prefix）、迴路位址（`osascript … with administrator privileges` 執行 `setup-loopback.sh install`），再以 `MACMEOW_PROGRESS=1` 執行 `play.sh`，解析 `@@STEP <id> <訊息>`（`common.sh` 的 `progress`）顯示進度。
  - 全部關閉：確認後執行 `play.sh stop`。
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
- Cyder `settings.json`：`wineLocale`、`graphicsBackend`、`msync`、`esync` → 保留，`uninstall.sh` 提示使用者自行調整。
- lo0 alias 與 `/Library/LaunchDaemons/tw.macmeow.loopback.plist` → `setup-loopback.sh uninstall`。
- `~/Library/Application Support/MacMeow/config`（`GAME_DIR=`、`MAPLE_SYNC=`）、`~/Library/Logs/MacMeow/`、App 偏好設定 `tw.macmeow.launcher`（SwiftUI 視窗位置）與 `~/Library/Saved Application State/tw.macmeow.launcher.savedState` → `uninstall.sh` 刪除。

## 環境變數

- `GAME_DIR`（預設 `~/Games/MapleStory`）：遊戲資料夾，需含 `MapleStory.exe`、`認證器.exe`、`貓貓TMS登入器.exe`、`HostShield.exe`、`XCGUI.dll`。
- `CYDER_ENGINE`（預設 `~/.cyder/runtime/Engines/wine-x86_64`）：Cyder engine 路徑。
- `MAPLE_SYNC`（預設 `msync`，可為 `none|msync|esync`）：寫入 Cyder 設定的同步模式。

## 外部變動時要更新的地方

- 私服更換連線位址：更新 `scripts/lib/common.sh` 的 `HOSTSHIELD_IPS`／`GAME_ALIAS_IP`；使用者需重新執行 `setup-loopback.sh install`。
- Cyder engine 的 CrossOver 基底改變：`patch-cyder-dlls.sh` 會拒絕套用。以新基底重建 DLL，並更新 `REQUIRED_BASE`、`patches/SOURCES.md`、`patches/bin/SHA256SUMS`。
- 伺服器要求的 `MapleStory.exe` 版本改變：更新 `README.md` 系統需求。
