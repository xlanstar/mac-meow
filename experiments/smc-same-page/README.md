# smc-same-page

- 問題：程式碼與頻繁寫入的變數同在一個 4 KB 頁時，Rosetta 的成本多高，換映射方式能否避開。
- 做法：x86_64 程式在 Rosetta 下反覆「寫變數、呼叫同頁程式碼」，量測每秒呼叫數。
  - `build/experiments/smc-same-page/smctest [sep]`：MAP_JIT RWX 頁；`sep` 把變數放到另一頁（對照組）。
  - `smctest2 0|1|2`：0 匿名 RWX（無 MAP_JIT）、1 共享記憶體 RWX、2 檔案私有映射 RWX。`1` 已知會卡住。
  - `smctest3`：程式碼放在不可執行（RW）頁。已知會卡住。
- 狀態：結論已記錄。
- 對應：technical-notes #9。
