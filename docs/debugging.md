# 除錯

診斷工具的使用注意事項與在 Rosetta 下除錯 Wine 程序的要點；一次性實驗見 [experiments/README.md](../experiments/README.md)。

## 診斷工具

`just`（即 `just --list`）列出所有指令與參數，完整用法、需求與副作用在各腳本開頭。常見的順序：

```sh
just sign-debug apply
just stack mach
just stack hitch
just sign-debug restore
just run-game trace
just wgui list
```

`--list` 看不出的事項：

- GUI Wine 程式需要 Aqua 工作階段（見 [AGENTS.md](../AGENTS.md#runtime-pitfalls)「Runtime pitfalls」）；各腳本是否自行經 Terminal.app 執行見腳本開頭。
- 不是 recipe 的工具：`tools/src/machstack/pesym.py`（Wine PE 位址 → 函式名）、`tools/src/machstack/hitchprof.py`（以其他門檻重新分析 `stack hitch` 的輸出）；用法見檔案開頭。
- bottle 內執行的工具（`wthreads.exe`、`recvcheck.exe`）：執行方式見原始碼開頭。

## 卡頓（FPS drop）

`just stack hitch` 在照常遊戲時連續取樣，同時要求 Metal HUD 產生效能報告（等同遊戲視窗選單 Metal HUD → Generate Performance Report），以報告的逐幀時間找出掉幀，比較「掉幀期間」與「平常」。需求與參數見 `stack.sh` 開頭。

- Metal HUD 的「記錄」功能（`MTL_HUD_LOG_ENABLED`、`ToggleLogEnabled`）不適用：遊戲中切換後沒有輸出；Cyder 收集 Wine stderr 的程式每累積 64 KB 才寫入 `last-wine-launch.log` 一次。
- 效能報告只有逐幀間隔、沒有時間戳，各幀時間由要求的時間推算（偏移見 `hitchprof.py` 的 `REPORT_LEAD_US`）。

報告的讀法：

- 「重點」只列各表增加最多的項目，是相關性，不一定是原因；先看它，再到下方的表與各次卡頓核對。
- 「HUD 整段統計」的 Command Buffer GPU 最大值遠小於卡頓幀的長度：卡頓在 CPU 端（沒有及時送出畫面），看執行緒與呼叫鏈。
- 主執行緒（整段 CPU 最多的執行緒，推定）卡頓時 CPU 反而下降：它在等待，「狀態」的系統呼叫（`mach_msg2`、`semaphore_wait`、`__psynch_cvwait` 等）與呼叫鏈指出在等誰。報告另外列出卡頓時狀態變化最大的執行緒（「狀態變化」0–1），CPU 用量小的執行緒也能找到。
- 「Rosetta 執行環境」在卡頓時增加：Rosetta 在翻譯新程式碼或處理自我修改程式碼的例外（見 [fixes.md #9](fixes.md#9-人多的地方很卡themida-vm--rosetta-smc未解)），通常伴隨 page fault 倍增。
- 其他程序的 CPU 在卡頓時增加（例如 `wineserver`、`BlackCipher64.aes`）：嫌疑在該程序。
- 呼叫鏈來自堆疊掃描（x86 碼多半沒有 frame pointer），會混入堆疊上殘留的舊返回位址；看卡頓與平常的差距，不要只看絕對比例。沒有符號的位置顯示為「模組+偏移」，同一偏移即同一呼叫點。

## Rosetta 除錯要點

- `sample`／`spindump` 會在 CoreSymbolication 內崩潰；程序凍結時 LLDB 無法暫停。改用 `just stack mach`（machstack：`task_for_pid` + `thread_get_state`）。
- Rosetta 下 x86 暫存器的位置見 `tools/src/machstack/machstack.c`（`[sp+8]` 暫存器區塊註解）。
- LLDB（含 watchpoint）可附加執行中的 Rosetta 程序並取得精確 x86 `rip`，但不認得 Wine PE 映像；用 `pesym.py` 對照位址。
- 區段表（`proc_pidinfo`／`mach_vm_region`）中 x86 shared cache 是唯讀、無路徑的 submap；判斷位址是否為系統函式庫程式碼要用 dyld 映像清單的 `__TEXT` 範圍（`machsample.c` 的 `scan_images`）。
