# 外部變動時要更新的地方

私服、Cyder、Homebrew、macOS 或本 repo 的識別資訊改變時，需要同步修改的地方。

- 私服更換連線位址：更新 `scripts/lib/common.sh` 的 `HOSTSHIELD_IPS`／`GAME_ALIAS_IP`；使用者需重新執行 `setup-loopback.sh install`。
- Cyder engine 的 CrossOver 基底改變：`patch-cyder-dlls.sh` 會拒絕套用（使用者看到的是 [known-issues.md #6](known-issues.md#6-cyder-更新後無法啟動)）。以新基底重建 DLL（[wine-patches.md](wine-patches.md)），並更新 `tools/dev/build-wine-dlls.sh` 的 `CX_VER`、`CX_SHA256`，`patch-cyder-dlls.sh` 的 `REQUIRED_BASE`，以及 `patches/SOURCES.md`、`patches/bin/SHA256SUMS`。
- Cyder engine 的 `winemac.so` 改變（任何 engine 更新都可能；修補不套用時的行為見 [scripts.md](scripts.md#patch-cyder-winemacsh)）：以 `otool -tV` 找出新版 `transformProcessToForeground:` 的對應指令，重新計算 `KNOWN_SHA256`、偏移與 RIP 相對位移（[fixes.md #10](fixes.md#10-dock-上有兩個楓之谷圖示隱藏登入器會讓遊戲斷線實驗性)）。
- Repo 改名或搬移：
  - 更新 `scripts/lib/common.sh` 的 `MACMEOW_REPO`，以及 `app/Sources/Services/AppPaths.swift` 的 `repo`、`latestRelease`。
  - 更新 Homebrew cask 範本 `packaging/homebrew/macmeow.rb` 的 `url`、`homepage`。
  - 已發佈的舊版 App 仍查詢舊網址，仰賴 GitHub 的轉址。
- 路徑、bundle id 或 LaunchDaemon label 改變：同步 cask 範本的 `uninstall quit:` 與 `zap`（對應 [external-state.md](external-state.md#清單) 中 `uninstall.sh` 刪除的項目）。App 名稱或腳本位置改變，或 `uninstall.sh` 的還原開始依賴 `scripts/` 以外的檔案時，同步 cask 的 `preflight_steps` 與 `uninstall script:`（見 [homebrew.md](homebrew.md#安裝與移除)）。
- Homebrew 改變程序命令列（`brew.rb <子指令>`）或 upgrade 時的 uninstall 流程：`uninstall.sh cask` 判斷不出時會當作移除（後果見 [homebrew.md](homebrew.md#安裝與移除)）；更新 `uninstall.sh` 的 `brew_subcommand`。Caskroom 的 `.metadata/config.json` 格式改變時，更新 `common.sh` 的 `homebrew_app`。
- 發佈附件命名、dmg 內容、bundle id 或簽章 Team ID 改變：舊版 App 的 `update.sh` 會拒絕更新（約定見 [scripts.md](scripts.md#updatesh)）。改變前先讓 `update.sh` 支援新格式並發佈一版。換 Team ID 時更新 `common.sh` 的 `MACMEOW_TEAM_ID`，使用者需手動下載一次。
- Cyder 改變圖形後端相關的行為（[fixes.md #13](fixes.md#13-圖形後端d3d11)）：
  - 啟動環境（`cyder-common.sh` 的 `cyder_apply_gptk_launch_environment`、`CYDER_GRAPHICS_*`、engine 的 `lib64/apple_gptk` 連結）：同步 `tools/game/run-game.sh` 中對應 `cyder_apply_gptk_launch_environment` 的環境變數區塊。
  - 可用條件（`cyder_d3dmetal_launch_allowed`、`cyder_dxmt_launch_allowed`、`cyder_dxvk_launch_allowed`、`cyder_preferred_gptk_root`、`cyder_gptk_root_is_valid`）或 `settings.json` 的 `graphicsBackend`／`graphicsHud`／`dxvkFrameRate` 值：同步 `common.sh` 的 `graphic_backend_available`、`gptk_complete` 與 `cyder-settings.sh`。
  - profile id 算法（`cyder-profile.sh` 的 `cyder_profile_id_for_path`）、`perProfile.<id>.environment` 格式或允許的環境變數（`cyder_game_environment_key_is_allowed`）：同步 `common.sh` 的 `cyder_profile_id` 與 `cyder-settings.sh`。
  - GPTK 改掉 `D3DM_MAX_FPS` 時，D3DMetal 的 FPS 上限會失效。
- 卡頓分析（`just stack hitch`，見 [debugging.md](debugging.md#卡頓fps-drop)）依賴的外部格式：
  - macOS 改變 Metal HUD 效能報告的觸發方式（Darwin notification `com.apple.metal.hud.notify.PerformanceReport-<秒數>s`）或檔名、位置：更新 `stack.sh` 的 `hud_report`、`new_report`。
  - 報告格式（HTML 內的 `frameintervals` JSON）、開始收集前的倒數或呈現相關的函式名稱改變：更新 `hitchprof.py` 的 `parse_report`、`FALLBACK_OFFSET_MS`、`PRESENT_MARKERS`，以及 `stack.sh` 的取樣長度。
- 登入器改名：更新 `common.sh` 的 `LAUNCHER_EXE` 與 `launcher-dock.sh` 的 `REG_SECTION`（格式見其註解）。登入器版面改變：更新 `tools/game/auto-start.sh` 開頭的視窗 class 與按鈕座標。
- 遊戲主程式改名或視窗標題改變：更新 `common.sh` 的 `GAME_EXE`、`GAME_WINDOW_TITLE`。
- macOS 28 移除一般用途的 Rosetta 2（Apple 的公告見 [known-issues.md #4](known-issues.md#4-macos-28-以後可能無法執行)）：
  - 整條執行鏈都依賴 Rosetta：Cyder engine 是 x86_64 Wine，`common.sh` 以 `arch -x86_64` 執行 Wine（`wineserver_kill`、`run_wine_tool`），`patches/bin` 的 DLL 與 `patch-cyder-loopback.sh` 的指令序列也都針對 x86_64 engine。
  - 若 Cyder 改用原生 ARM64 Wine（CrossOver 已有 ARM64 預覽版，以 FEX 模擬 x86），上述修補都要重新驗證或重做。
  - macOS 28 確認相容（或確認不支援）後，更新 `README.md` 的已知問題與系統需求，以及 `docs/known-issues.md`。
