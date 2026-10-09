# 技術筆記

每個問題的根因與修補。執行鏈與連線路徑見 [architecture.md](architecture.md)。

新增問題時沿用相同格式：症狀、根因、修補，必要時加上證據（使用的工具與數據）。只寫結論，不放原始記錄或個人資料。

## 1. HostShield 無法監聽

- 症狀：HostShield 啟動失敗。
- 根因：macOS `lo0` 只有 127.0.0.1；Windows 整段 127/8 都是本機。
- 修補：`setup-loopback.sh` 加 lo0 alias 與 LaunchDaemon。

## 2. 4 個 HostShield 互搶 port 後全部退出

- 根因：Cyder/CrossOver 的 wineserver 把 `bind(127.x.x.x)` 改寫成 127.0.0.1（`connect` 不改寫）。
- 修補：`patch-cyder-loopback.sh` 把 wineserver 的條件跳躍 `jne` 改成 `jmp`（1 byte）。

## 3. 「無法登入伺服器」（`CONNECT_TO_LOGIN_FAILED`）

- 根因：登入器以 `netsh int ip add addr 1 202.80.104.28` 把官方 IP 掛到 Loopback，但 Wine 的 netsh 是 stub。
- 修補：`setup-loopback.sh` 一併把 202.80.104.28 掛到 lo0。

## 4. 認證器打不開

- 根因：VB6 程式需要 `MSVBVM60.DLL`。
- 修補：Cyder winetricks `vb6run`。

## 5. 亂碼、設定未套用

- 根因：Cyder 只在直接開 `MapleStory.exe` 時套用楓之谷設定；本流程是從 `認證器.exe` 開始。
- 修補：Cyder 全域設定 `wineLocale=zh_TW`、`graphicsBackend=d3dmetal`（無法使用時 `dxmt`，#13）。

## 6. 遊戲啟動約 2 秒後凍結（recv 無限遞迴）

- 症狀：無視窗、CPU 0%、LLDB 無法暫停。
- 證據：machstack（`tools/stack.sh mach`）取得 Rosetta 致命訊息 `unexpectedly need to EmulateForward on a synchronous exception`，出錯點是 `ntdll!pf_fill_left_a` 的 `push`；該執行緒 1 MB 堆疊用盡，堆疊上有 2 萬多個相同返回位址 `MachineIdLib.dll+0x89db`。
- 根因：登入器放入的 `MachineIdLib.dll` 以 Detours 分別 hook `wsock32!recv` 與 `WS2_32!recv`，兩者共用同一個「原始函式」指標。Windows 的 `wsock32!recv` 是獨立函式，Wine 的卻是 `ws2_32.recv` forwarder，因此同一函式被 hook 兩次，`recv` 自我遞迴到堆疊溢位。Rosetta 無法處理這個同步例外，例外伺服器在 abort 途中卡住，Wine 收不到 `c00000fd`，整個程序凍結。
- 修補：`patches/wsock32-distinct-recv.patch` 讓 `wsock32!recv` 成為獨立函式並呼叫 `WSARecv`，任何 hook 順序都不會繞回。

## 7. 進入遊戲世界 <1 FPS（rsaenh.dll 反覆載入）

- 證據：`+virtual` trace 中登入畫面 80 秒內 `rsaenh.dll` 被映射 23,309 次；`+crypt` 中 `CryptAcquireContextW` 單秒可達 2,113 次。
- 根因：Wine 的 `CRYPT_LoadProvider` 每次都 `LoadLibrary` CSP，`CryptReleaseContext` 時 `FreeLibrary`。Windows 上很便宜，Rosetta 上每次重新映射都要重新翻譯 x86 程式碼。
- 修補：`patches/advapi32-pin-csp.patch` 在 CSP 載入後以 `GetModuleHandleEx(PIN)` 常駐。映射次數 23,309 → 11。

## 8. 一般卡頓

- 根因：Cyder 預設不開 MSync。
- 修補：`cyder-settings.sh`（由 `play.sh` 呼叫）設定 `msync=true`。

## 9. 人多的地方很卡（Themida VM × Rosetta SMC，未解）

- 證據：
  - LLDB 取樣：遊戲世界中主執行緒 78% 時間在 `.themida`（Themida 虛擬機）。
  - VM 每次進出寫入鎖變數 `0x14aa316a4`（watchpoint 確認寫入指令 `0x14ae588a6` 等），它與 VM handler 跳躍表程式碼（`0x14aa31cae`…）同在 4 KB 頁 `0x14aa31000`。
  - 熱鬧城鎮（頻道 1）對比人少地方：VM 鎖切換 23,000 對 7,500 次/秒；page fault 75,000 對 13,700 次/秒；主執行緒 CPU 約 100% 對 32%；Rosetta exceptionserver CPU 21.5% 對 4.3%。
  - `tools/src/smctest`：程式碼與頻繁寫入的變數同頁時慢約 11,500 倍。
- 根因：x86 CPU 以快取行偵測自我修改程式碼，不同行就沒有成本；Rosetta 以整頁保護已翻譯的程式碼，每次寫入都要「例外、讓翻譯失效、重新翻譯、重新保護」。VM 呼叫次數與畫面上的玩家、特效數量成正比。
- 已試無效：Rosetta 隱藏環境變數（`ROSETTA_*`、`CAMBRIA_*`）、MAP_JIT、一般 RWX、共享或檔案映射、不可執行頁。
- 結論：根治需改動遊戲記憶體，會碰到 Themida/NGS 防外掛，不採用。使用者只能避開人多的頻道與地圖。

## 10. Dock 上有兩個楓之谷圖示（隱藏登入器會讓遊戲斷線，未採用）

- 症狀：開始遊戲後，Dock 上同時有登入器與遊戲兩個 `wine` 圖示。登入器會一直把自己縮到最小，手動打開又會立刻縮小。
- 根因：每個 Wine 程式都是獨立的 macOS 程序。`winemac.drv` 在程式第一次顯示視窗時（`-[WineApplicationController transformProcessToForeground:]`）把它設成一般 App（`NSApplicationActivationPolicyRegular`），之後不會改回。登入器在遊戲執行期間要轉發遊戲連線（見 [architecture.md](architecture.md) 的連線路徑），不能關閉。
- 不可行的做法：
  - Wine 的 `Mac Driver` 登錄選項沒有 Dock 相關設定。
  - CrossOver 的不顯示 Dock 清單（`CW HACK 24141`）比對的是 macOS 執行檔名稱，在 Cyder 中所有程式都叫 `wine`；而且那個清單會讓程式維持 Prohibited，視窗無法輸入。
  - 從其他程序修改：`lsappinfo setinfo <ASN> -uielement` 回傳成功，但 LaunchServices 不會套用。
  - 以 CrossOver 原始碼重建 `winemac.so`：Cyder 的 `winemac.so` 另含 Cyder 自己的楓之谷修補（`engine-manifest.json` 列出的 `maplestory-cx26-*`、`a6-final-same-view-backing-sync` 等，字串如 `MapleStoryPort: not bringing BlackXchg.aes to the foreground`），部分修補的原始碼沒有公開，重建會把這些修補拿掉。
- 驗證：以 Swift 測試程式確認輔助程式（`NSApplicationActivationPolicyAccessory`）沒有 Dock 圖示，縮到最小的視窗也不會留在 Dock，而且仍可用 `deminiaturize` 還原。
- 修補：`patch-cyder-winemac.sh` 只改 Cyder engine 的 `winemac.so` 內上述方法的兩段指令（只套用到 SHA-256 已知的檔案，改完重新 ad-hoc 簽章；`wine` 有 `disable-library-validation`）：
  - `setActivationPolicy:` 的參數從固定的 `0`（Regular）改成讀取 `capture_displays_for_fullscreen`（依程式讀取的 `CaptureDisplaysForFullscreen` 登錄值，`0` 或 `1`），值為 `1` 時成為 Accessory。原本經由 GOT 呼叫的 `objc_msgSend` 改為 `callq *%r12`（同一函式），空出的位元組放得下新指令。
  - 「已轉成前景程式就返回」的檢查從 `policy == Regular` 改成 `policy != Prohibited`，避免 Accessory 程式每次顯示視窗都重建選單並搶走焦點。
  - `launcher-dock.sh` 只對 `貓貓TMS登入器.exe` 寫入 `AppDefaults\貓貓TMS登入器.exe\Mac Driver\CaptureDisplaysForFullscreen=y`。其他程式（包含 `MapleStory.exe`）的值是預設的 `n`，行為不變。這個值原本只影響全螢幕時是否鎖定螢幕，登入器不會全螢幕。
  - 登入器沒有 Dock 圖示時，Wine 會在程式被啟用時還原縮到最小的視窗（`applicationDidBecomeActive:` → `unminimizeWindowIfNoneVisible`），MacMeow 的「顯示登入器」就是啟用該程序。
- 結果：`lsappinfo` 顯示登入器為 `UIElement`，Dock 的項目清單中沒有登入器；登入器視窗照常顯示並完成載入。但按「開始遊戲」後，遊戲顯示「與登入伺服器連線中斷」：
  - 遊戲的連線經過登入器在 `202.80.104.28:37629` 的轉發；此時直接連 HostShield（`127.145.37.1:37629`）可立即收到伺服器的 handshake，經登入器轉發則沒有回應。
  - 同一台機器把登入器改回一般 App（刪除登錄值）後，遊戲可以正常登入。輔助程式在視窗縮到最小後轉發停擺的確切原因（例如 macOS 對沒有可見視窗的輔助程式節流）尚未查明。
  - 結論：改為實驗性，預設關閉（`MACMEOW_HIDE_LAUNCHER_DOCK=1` 才套用），App 不提供選項；未啟用時 `play.sh` 會刪除登錄值並還原 `winemac.so`。

## 11. 關閉遊戲後登入器與 Wine 程式殘留

- 症狀：關閉遊戲後登入器還開著；兩個都關閉後，背景仍有十多個 `wine` 程序，只有「全部關閉」能清乾淨。
- 根因：
  - 登入器在 Windows 上本來就不會隨遊戲關閉。
  - `認證器.exe` 啟動的 4 個 `HostShield.exe`（各有一個 `conhost.exe`）不會自行結束。Wine 的 wineserver 要等所有非系統程式結束後，才會通知 `services.exe`、`explorer.exe` 等系統程式關閉（`server/process.c` 的 `user_processes`），所以整個 Wine 一直留著。
  - Cyder 0.13.2 可能留下一組 `CyderSwift --sentinel-connect` 與其 `bash`：supervisor 關閉 fifo 寫入端後，較晚啟動的 helper 卡在阻塞的 `open(fifo)`。Cyder `cyder/lifecycle-ux`（0.14.0-rc.1，commit `ed9e89e`）已修正。
- 修補：`session.sh` 在背景監看本專案的程式（以命令列開頭是遊戲資料夾的 Windows 路徑，或 `HostShield.exe`／`認證器.exe` 來判斷）。遊戲關閉，或登入器關閉且遊戲沒在執行，連續 3 次檢查（約 6 秒）都成立就結束這些程式。Patcher 這類其他程式執行中時不收尾。只結束本專案的程式，Wine 會自行關閉，其他 Cyder 遊戲不受影響；有其他 Windows 程式時不等待 Wine 結束；Wine 沒有自行結束、也沒有其他 Windows 程式時，才執行 `wineserver -k`。`play.sh` 啟動時若只剩 `認證器.exe`／`HostShield.exe` 殘留，也以同樣方式收尾（`session.sh close`，會先停止舊的監看程序，以免它沿用上一次的狀態），不再對整個 shared bottle 執行 `wineserver -k`。Wine 結束後再結束 fifo 已刪除或監督程序已結束（PPID 1）的 sentinel。
- 結果：關閉登入器後，4 秒內 HostShield、`conhost` 與所有 Wine 系統程式都結束；當時殘留的 11 組 sentinel 也一併清除。

## 12. 更換遊戲字型（Wine 端無效，未採用）

- 目標：不修改遊戲檔，從 Wine 端把遊戲文字換成其他字型（例如微軟正黑體）。
- 已試，遊戲文字都沒有變：
  - Wine 的 `HKCU\Software\Wine\Fonts\Replacements` 把細明體、新細明體、MingLiU、PMingLiU 與韓服 UI 沿用的 Dotum／돋움／Gulim／굴림 對應到新字型。Wine 只在要求的字型不存在時才套用替換（`win32u/font.c` 的 `add_family_replacement`），使用者裝了 `mingliu.ttc` 時無效。
  - `HKLM\…\FontSubstitutes` 寫入相同名稱。Wine 11 的 `find_matching_face_by_name` 也是先找原名稱，找不到才用替代名稱，結果同上。
  - 暫時移走 `mingliu.ttc`：遊戲程序改為映射 `simsun.ttc`，字形仍是明體。
  - `FontLink\SystemLink` 把 `MSJH.TTC,Microsoft JhengHei UI` 移到 Tahoma、Microsoft Sans Serif、Lucida Sans Unicode、MS UI Gothic 的第一順位：遊戲程序改為映射 `msjh.ttc`／`msjhbd.ttc`、不再映射 `mingliu.ttc`，但遊戲畫面上的文字仍然沒變。
- 證據：以 `lsof -p <MapleStory.exe>` 看 Wine 映射的字型檔。原本 CJK 來自 Tahoma 的 SystemLink（第一順位 MINGLIU.TTC，其次 SIMSUN.TTC），所以 Wine 端設定確實生效，只是不影響主要的遊戲文字。
- 遊戲端：`Gr2D_DX11.dll` 內含 FreeType；WZ 有內嵌字型（`FONT_DATA`，Etc 下的 `NANUMGOTHIC*.img`、`SEOULNAMSAN*.img`、`YUNGOTHIC250.img` 等韓文字型），UI 節點以 `font` 指定字型名稱（Nanum Gothic、Dotum、Arial 等）。
- 可能原因（未證實）：遊戲要求一個 bottle 內沒有的字型名稱，Wine 再以 `find_any_face` 依序挑第一個支援該字集的家族（每次都映射的 `AppleLiSung-Light.ttf` 是明體，與畫面一致）；或主要文字使用遊戲自己的字型資料。
- 下一步（若要繼續）：以 `tools/run-game.sh` 搭配 `EXTRA_DEBUG=MapleStory.exe:+font` 記錄遊戲要求的字型名稱與實際選到的字型。若是不存在的名稱，可用 Replacements 指定；若是遊戲自帶的字型資料，不改遊戲檔就無法更換。
- 附帶發現：Wine 依 locale 決定字碼頁，與 bottle 的 `Fonts\Codepages` 不同時，任何 Wine 程式啟動都會改寫語系相依的字型設定（`Codepages`、FontSubstitutes 的 `MS Shell Dlg`／`Tms Rmn`、FontLink）。從 `LANG=C` 的 shell 執行 `reg` 曾把 shared bottle 從 950 改成 1252，所以 `export_wine_env` 固定使用 `zh_TW.UTF-8`（與 Cyder 的 `wineLocale=zh_TW` 相同）。

## 13. 圖形後端（D3D11 經 DXMT 轉 Metal）

- 結論：遊戲以 D3D11 繪圖，`graphicsBackend=dxmt`（#5）讓它直接走 DXMT（D3D11 → Metal）。以下證據取自改預設為 D3DMetal 之前。
- 證據：遊戲執行中以 `lsof -p <MapleStory.exe>` 檢查。遊戲是 64 位元，繪圖模組為 `Gr2D_DX11.dll`；`d3d11.dll`、`dxgi.dll`、`winemetal.dll` 來自 Cyder 的 `~/.cyder/runtime/graphics/dxmt/<版本>/`，而非 Wine 內建；DXMT 的 shader 快取（`$TMPDIR/../C/dxmt/MapleStory.exe/`）在遊戲啟動後隨即被寫入。
- 同程序也映射 Wine 內建的 `d3d9.dll`、`wined3d.dll`、`opengl32` 與 MoltenVK，推測是 `NxOverlay_x64.dll` 偵測或 hook 時載入，不是主要繪圖路徑（未以 `+loaddll` 確認載入者）。
- 其他後端：Cyder 也支援 `d3dmetal`（Apple GPTK 的 D3DMetal，支援 D3D11／12；需要 macOS 14 以上與使用者自行安裝的 GPTK 或 CrossOver，不能隨本專案散布）、`dxvk`（D3D11 → Vulkan → MoltenVK → Metal）與 `wined3d`（OpenGL）。Cyder 對楓之谷的自動選擇是 macOS 15 以上用 DXMT，否則 DXVK，不會自動選 D3DMetal。
- 本專案現在預設 D3DMetal（`MACMEOW_GRAPHICS_BACKEND=d3dmetal`，App 可改選 DXMT）。Cyder 遇到無法使用的 `graphicsBackend=d3dmetal`（macOS 14 以下或找不到 GPTK）不會退回 DXMT，而是改用 default 且停用楓之谷的自動選擇，結果是 Wine 內建的 wined3d；所以 `cyder-settings.sh` 以與 Cyder 相同的條件（`d3dmetal_available`）檢查，無法使用時寫入 `dxmt`。Cyder 以 `dxvkFrameRate`（預設 60）設定 DXMT 的 `d3d11.preferredMaxFrameRate`，所以 DXMT 下 FPS 預設上限 60；Cyder 不替 D3DMetal 設定 FPS 上限（`cyder_apply_graphics_runtime_preferences`）。效能 HUD 用 `graphicsHud=metal`（Cyder 匯出 `MTL_HUD_ENABLED=1`），DXMT 與 D3DMetal 都經 Metal 繪圖，兩者都適用。
- D3DMetal 的 FPS 上限：`D3DMetal.framework` 讀取環境變數 `D3DM_MAX_FPS`（未公開文件）。以 `MACMEOW_GRAPHICS_BACKEND=d3dmetal MACMEOW_HUD=1 tools/run-game.sh` 在登入畫面實測（M4 Max、120Hz 螢幕）：`EXTRA_ENV="D3DM_MAX_FPS=30"` 時 HUD 為 30.00 FPS／33.33 ms；不設時約 117 FPS／8.5 ms，即預設只受螢幕更新率限制。HUD 同時確認 D3DMetal（Game Porting Toolkit 4.0b2）已接手 D3D11。
- FPS 上限的做法：Cyder 的 `dxvkFrameRate` 只套用到 DXVK／DXMT，`D3DM_MAX_FPS` 也不在 Cyder 匯出的變數裡；本專案的啟動流程（`open -a Cyder` 開 `認證器.exe`）也無法直接帶環境變數。Cyder 會把 `settings.json` 的 `perProfile.<id>.environment`（`<id>` 為 exe 實際路徑 SHA-256 的前 24 個十六進位字元）匯出給該 exe，而 Wine 以父程序的環境建立子程序，所以寫在 `認證器.exe` 的 profile 就會傳到登入器與 `MapleStory.exe`。實測：以 `play.sh` 正常啟動、`MACMEOW_MAX_FPS=60`，D3DMetal 的 HUD 為 59.75 FPS／16.74 ms；手動寫入 `D3DM_MAX_FPS=30` 時為 29.97 FPS。
- 未比較 DXMT 與 D3DMetal 的效能。遊戲是 2D，已知的效能問題都在 CPU 端（#7–#9），預期更換圖形後端的效果有限。要實測時以 `MACMEOW_GRAPHICS_BACKEND=dxmt|d3dmetal MACMEOW_HUD=1 bash tools/run-game.sh` 在同一張地圖比較 FPS 與 CPU。

## 其他觀察

- 官方 `Patcher.exe` 曾被觸發一次，把 `MapleStory.exe` 換成官方 6.282.5.0，伺服器回報「不正確的版本」。觸發者未查明，之後未再發生。
- 登入器程序約有 1,600 條執行緒，不影響運作，未深入。
