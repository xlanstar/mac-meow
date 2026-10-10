# smc-same-page

- 問題：程式碼與頻繁寫入的變數同在一個 4 KB 頁時，Rosetta 的成本多高，換映射方式能否避開。
- 做法：x86_64 程式在 Rosetta 下反覆「寫變數、呼叫同頁程式碼」，量測每秒呼叫數；各參數見原始碼開頭。
  - `build/experiments/smc-same-page/smctest [sep]`
  - `build/experiments/smc-same-page/smctest2 0|1|2`
  - `build/experiments/smc-same-page/smctest3`
- 狀態：結論已記錄（修補本身未解）。
- 對應：fixes #9。
