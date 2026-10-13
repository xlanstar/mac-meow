# smc-cost

- 問題：Rosetta 處理「程式碼與頻繁寫入的變數同頁」（SMC）時，成本由哪些部分組成（偵測粒度、重新翻譯、例外路徑、排程、配置方式），哪些能從 Wine 或系統端調整；遊戲中的 SMC 速率如何不碰遊戲就量到。
- 做法：x86_64 程式在 Rosetta 下改變單一因素量測每次「寫入 → 執行」的成本與計數，原生程式量測作業系統例外路徑的下限，另以 `proc_pidinfo` 唯讀觀察執行中程序的 SMC 速率；各參數見原始碼開頭。
  - `build/experiments/smc-cost/smcprobe offset|blocks|size|other|writes|calls|samebytes|modbytes|timeline|map|stages|thread ...`
  - `build/experiments/smc-cost/excfloor [秒數]`
  - `build/experiments/smc-cost/smcrate <pid> [秒數] [間隔 ms]`（可用於執行中的遊戲：唯讀、不暫停）
  - `build/experiments/smc-cost/noexc <程式> [參數...]`（從 agent 工具等啟動時，先清除繼承的例外 port，崩潰才不會看起來像卡住）
- 狀態：未解（量測結果待記錄到 fixes.md）。
- 對應：fixes #9。
