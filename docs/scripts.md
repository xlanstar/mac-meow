# 使用者腳本

`scripts/` 各腳本的角色、相依與從程式碼不容易看出的行為；用法與子指令見各腳本開頭。

這些腳本由 `app/build-app.sh` 打包進 `MacMeow.app`（見 [app.md](app.md#建置與-dmg)），App 只透過它們動作。修改的 repo 以外狀態與還原方式見 [external-state.md](external-state.md)。

## `lib/common.sh`

所有使用者腳本（以及 `tools/lib.sh`）共用的路徑、常數（遊戲檔案、HostShield 與迴路位址、發佈與 Homebrew 識別）、設定（`load_settings`，見 [settings.md](settings.md)）與函式。

- 本專案的程式一律以 `session_procs` 判斷（`play.sh`、`session.sh` 共用；比對規則見其註解）。
- 圖形後端：
  - 退回順序見 `common.sh` 的 `GRAPHIC_BACKENDS`（`effective_graphic_backend` 依此退回）。
  - `graphic_backend_available` 的條件必須與 Cyder 的 `cyder_<後端>_launch_allowed` 相同（為何要相同見 [fixes.md #13](fixes.md#13-圖形後端d3d11)）；條件見其實作與 `gptk_complete`。
- `engine_running`（任何 bottle，保護 engine，見 [external-state.md](external-state.md#engine-修補的共同保證)）與 `wine_running`（只看 shared bottle）的差別見 `common.sh` 註解。
- `progress`：App 的進度介面（格式見其註解，App 端見 [app.md](app.md#擴充-app)）。

## `lib/engine-patch.sh`

engine 執行檔位元組修補的共用流程（`patch-cyder-loopback.sh`、`patch-cyder-winemac.sh`；介面見檔案開頭）。共同保證見 [external-state.md](external-state.md#engine-修補的共同保證)。

## `play.sh`

入口：檢查環境、套用需要的修補與設定，再照官方流程從 `認證器.exe` 啟動（步驟見 `cmd_start` 的編號註解）。

- `status --porcelain` 是 App 的狀態來源：key 定義在 `porcelain()`，與 `app/Sources/Core/EnvStatus.swift` 對應（見 [app.md](app.md#擴充-app)）。

## `setup-loopback.sh`

替 lo0 加上 `common.sh` 的 `LOOPBACK_IPS`，並安裝開機時重新加上的 LaunchDaemon（`setup-loopback.sh` 的 `LABEL`）。各位址的用途見腳本開頭與 [fixes.md #1](fixes.md#1-hostshield-無法監聽)、[#3](fixes.md#3-無法登入伺服器connect_to_login_failed)。App 端見 [app.md](app.md#功能)。

## `patch-cyder-loopback.sh`

把 wineserver「bind 127.x.x.x 一律改成 127.0.0.1」的判斷改 1 byte 跳過（[fixes.md #2](fixes.md#2-4-個-hostshield-互搶-port-後全部退出)）。

## `patch-cyder-dlls.sh`

以 `patches/bin` 的 DLL 取代 engine 內建版（[fixes.md #6](fixes.md#6-遊戲啟動約-2-秒後凍結recv-無限遞迴)、[#7](fixes.md#7-進入遊戲世界-1-fpsrsaenhdll-反覆載入)）。

- 基底改變時見 [upstream-changes.md](upstream-changes.md)。
- 重建 DLL 見 [wine-patches.md](wine-patches.md)。

## `patch-cyder-winemac.sh`

實驗性：改 engine `winemac.so` 兩段指令，讓設了 `CaptureDisplaysForFullscreen=y` 的程式成為沒有 Dock 圖示的輔助程式（[fixes.md #10](fixes.md#10-dock-上有兩個楓之谷圖示隱藏登入器會讓遊戲斷線實驗性)）。

- engine 的 `winemac.so` 不是已知版本時不修改，登入器照常顯示在 Dock。

## `cyder-settings.sh`

寫入 Cyder 的 `settings.json`：全域設定與 `認證器.exe` 的 `perProfile.<id>.environment.D3DM_MAX_FPS`（key 與原因見腳本開頭，各設定的作用見 [settings.md](settings.md#變數)）。

- `restore` 不讀取設定，使用者事後改過的值保留（判斷規則見腳本開頭與 `SPEC`）。

## `quarantine.sh`

移除遊戲資料夾的 `com.apple.quarantine`（記錄與還原見腳本開頭）。

## `launcher-dock.sh`

在 shared bottle 登錄寫入或刪除登入器的 `CaptureDisplaysForFullscreen=y`；engine 套用 `patch-cyder-winemac.sh` 後登入器才會因此隱藏 Dock 圖示（[fixes.md #10](fixes.md#10-dock-上有兩個楓之谷圖示隱藏登入器會讓遊戲斷線實驗性)）。

## `session.sh`

遊戲關閉後自動結束本專案的程式（判斷條件與原因見 [fixes.md #11](fixes.md#11-關閉遊戲後登入器與-wine-程式殘留)；監看方式見腳本開頭與 `cmd_watch`）。

## `update.sh`

App 的一鍵更新（App 端流程見 [app.md](app.md#功能)）；用法見腳本開頭。

- 與發佈的約定：`update.sh` 的下載網址與 dmg 內容（`cmd_prepare`）必須與 `release.sh` 的產物一致，新版必須符合 `common.sh` 的 `MACMEOW_REQUIREMENT`（非 ad-hoc 的發佈由 `release.sh` 的 `verify_dmg` 事先檢查）。改變任何一項見 [upstream-changes.md](upstream-changes.md)。
- 安全性：信任只來自 `MACMEOW_REQUIREMENT`（見 `common.sh` 註解）；`.sha256` 只確認下載完整。

## `report.sh`

問題回報的診斷資訊（App 的「回報問題」使用，見 [app.md](app.md#功能)）；內容與遮蔽規則見腳本開頭與 `summary`、`bundle`、`redact`。

## `uninstall.sh`

還原 [external-state.md](external-state.md#清單) 中所有可還原的項目；各子指令與執行位置見腳本開頭，測試方式見 [development.md](development.md#測試-uninstallsh)。

- 還原只能用到 `scripts/` 內的檔案（Caskroom 只複製 `scripts/`）。
