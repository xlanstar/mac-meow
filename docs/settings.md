# 遊戲設定與環境變數

使用者腳本讀取的遊戲設定：值的來源與優先序，以及每個變數的作用。建置與簽章用的變數見 [signing.md](signing.md)。

## 來源與優先序

- 來源與優先序（環境變數、App 的設定檔、預設值）見 `common.sh` 的 `MACMEOW_SETTINGS` 與 `load_settings` 註解。
- 名稱、預設值與允許值只定義在 `common.sh` 的 `MACMEOW_SETTINGS`；App 端的預設值與選項在 `app/Sources/Core/AppConfig.swift`，兩邊要一致。

## 變數

- `GAME_DIR`（設定檔 key 同名）：遊戲資料夾，需含 `common.sh` 的 `GAME_FILES`；預設值見 `common.sh` 的 `load_settings`。
- `CYDER_ENGINE`：Cyder engine 路徑（預設值見 `common.sh` 開頭的路徑區）；不讀設定檔。
- `MACMEOW_SYNC`：同步機制（為何預設 MSync 見 [fixes.md #8](fixes.md#8-一般卡頓)）。
- `MACMEOW_GRAPHICS_BACKEND`：圖形後端；無法使用時自動退回（見 [scripts.md](scripts.md#libcommonsh)）。
- `MACMEOW_MAX_FPS`：FPS 上限（DXMT／DXVK 與 D3DMetal 的寫法見 `cyder-settings.sh` 開頭）。
- `MACMEOW_HUD`：Metal 效能 HUD（顯示 FPS）。
- `MACMEOW_AUTO_CLOSE`：遊戲關閉後自動收尾（見 [fixes.md #11](fixes.md#11-關閉遊戲後登入器與-wine-程式殘留)）。
- `MACMEOW_HIDE_LAUNCHER_DOCK`（實驗性，App 不提供這個選項）：隱藏登入器的 Dock 圖示；開啟後遊戲會與登入伺服器斷線（[fixes.md #10](fixes.md#10-dock-上有兩個楓之谷圖示隱藏登入器會讓遊戲斷線實驗性)）。關閉時 `play.sh` 還原修補與登錄設定（條件見 `cmd_start` 的步驟 3 註解）。

`MACMEOW_PROGRESS`、`MACMEOW_VERSION` 不是設定，是 App 呼叫腳本時的介面（見 [scripts.md](scripts.md#libcommonsh) 的 `progress` 與 `report.sh` 開頭）。
