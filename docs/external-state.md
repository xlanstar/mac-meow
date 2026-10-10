# 外部狀態

本專案在 repo 以外修改的所有狀態，以及各自的還原方式；`uninstall.sh` 依這份清單還原（見 [scripts.md](scripts.md#uninstallsh)）。

## 清單

格式：位置：變更內容 → 還原方式。

- Cyder engine（`common.sh` 的 `CYDER_ENGINE`）：wineserver 與 DLL 被修補；開發時 wine 執行檔可能換成除錯簽章（`common.sh` 的 `DEBUG_SIGN_FILES`）。原檔備份為 `*.macmeow-orig`，DLL 另有 `*.macmeow-applied` 標記 → `patch-cyder-loopback.sh restore`、`patch-cyder-dlls.sh restore`、`common.sh` 的 `debug_sign_restore`；還原後刪除備份。
- Cyder engine `lib/wine/x86_64-unix/winemac.so`：兩段指令被修補並重新 ad-hoc 簽章；原檔備份為 `winemac.so.macmeow-orig` → `patch-cyder-winemac.sh restore`（`uninstall.sh` 呼叫；`MACMEOW_HIDE_LAUNCHER_DOCK` 未開啟時 `play.sh` 也會還原，見 [settings.md](settings.md#變數)）。
- Cyder shared bottle（`common.sh` 的 `SHARED_BOTTLE`）：安裝 `vb6run` → 保留：shared bottle 由所有 Cyder 遊戲共用，其他程式也可能依賴這個 VB6 執行環境，而且 winetricks 沒有對應的移除功能。
- Cyder shared bottle 登錄（`user.reg`）：登入器的 `CaptureDisplaysForFullscreen`（`launcher-dock.sh` 的 `KEY`）→ `launcher-dock.sh restore`（`uninstall.sh` 呼叫；`MACMEOW_HIDE_LAUNCHER_DOCK` 未開啟時 `play.sh` 也會呼叫，見 [settings.md](settings.md#變數)）。不備份原值，直接刪除：假設使用者不會自行替登入器設定這個值。
- Cyder 的程序：`session.sh` 在 Wine 結束後結束 Cyder 遺留的 `CyderSwift --sentinel-connect`（條件見 `session.sh` 的 `cleanup_sentinels`）→ 不需還原：這些程序不會再被 Cyder 使用，只是沒有自行退出，結束它們不會留下需要還原的狀態。
- Cyder `settings.json`（`common.sh` 的 `CYDER_SETTINGS`）：`cyder-settings.sh` 的 `SPEC` 列出的 key；原檔備份為 `settings.json.macmeow-orig` → `cyder-settings.sh restore`（還原後刪除備份）。
- 遊戲資料夾內項目的 `com.apple.quarantine` xattr 被移除；原值記錄在 `quarantine.sh` 的 `BAK`（在 `MACMEOW_SUPPORT` 內）→ `quarantine.sh restore`（`uninstall.sh` 在刪除 MacMeow 設定資料夾之前呼叫）。
- lo0 alias（`common.sh` 的 `LOOPBACK_IPS`）與 LaunchDaemon（`setup-loopback.sh` 的 `PLIST`）→ `setup-loopback.sh uninstall`。
- MacMeow 自己的資料 → `uninstall.sh purge` 整個刪除：`common.sh` 的 `MACMEOW_SUPPORT`（含設定檔，key 見 [settings.md](settings.md)）、`MACMEOW_LOGS`、`MACMEOW_CACHE`，以及 `MACMEOW_BUNDLE_ID` 的偏好設定與 Saved Application State（見 `cmd_purge`）。

## Engine 修補的共同保證

適用於所有修改 Cyder engine 的 `apply`／`restore`（`patch-cyder-*.sh` 與 `debug_sign_restore`）：

- Cyder 的 Wine 執行中一律拒絕。判斷的是這個 engine 的任何 wineserver，不只 shared bottle，因為所有 bottle 共用 engine（`common.sh` 的 `require_wine_stopped`）。
- `restore` 只在目前檔案仍是本專案的修補版時才寫回備份；engine 已被 Cyder 更新時只刪除過期備份，避免把舊檔蓋回新 engine。
