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
- 修補：Cyder 全域設定 `wineLocale=zh_TW`、`graphicsBackend=dxmt`。

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
- 修補：`play.sh` 設定 `msync=true`。

## 9. 人多的地方很卡（Themida VM × Rosetta SMC，未解）

- 證據：
  - LLDB 取樣：遊戲世界中主執行緒 78% 時間在 `.themida`（Themida 虛擬機）。
  - VM 每次進出寫入鎖變數 `0x14aa316a4`（watchpoint 確認寫入指令 `0x14ae588a6` 等），它與 VM handler 跳躍表程式碼（`0x14aa31cae`…）同在 4 KB 頁 `0x14aa31000`。
  - 熱鬧城鎮（頻道 1）對比人少地方：VM 鎖切換 23,000 對 7,500 次/秒；page fault 75,000 對 13,700 次/秒；主執行緒 CPU 約 100% 對 32%；Rosetta exceptionserver CPU 21.5% 對 4.3%。
  - `tools/src/smctest`：程式碼與頻繁寫入的變數同頁時慢約 11,500 倍。
- 根因：x86 CPU 以快取行偵測自我修改程式碼，不同行就沒有成本；Rosetta 以整頁保護已翻譯的程式碼，每次寫入都要「例外、讓翻譯失效、重新翻譯、重新保護」。VM 呼叫次數與畫面上的玩家、特效數量成正比。
- 已試無效：Rosetta 隱藏環境變數（`ROSETTA_*`、`CAMBRIA_*`）、MAP_JIT、一般 RWX、共享或檔案映射、不可執行頁。
- 結論：根治需改動遊戲記憶體，會碰到 Themida/NGS 防外掛，不採用。使用者只能避開人多的頻道與地圖。

## 其他觀察

- 官方 `Patcher.exe` 曾被觸發一次，把 `MapleStory.exe` 換成官方 6.282.5.0，伺服器回報「不正確的版本」。觸發者未查明，之後未再發生。
- 登入器程序約有 1,600 條執行緒，不影響運作，未深入。
