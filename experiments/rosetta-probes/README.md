# rosetta-probes

- 問題：臨時探測 Rosetta 下執行中的程序：CPU 最高的執行緒在跑哪條呼叫鏈、某位址有哪些字串。
- 做法：以 Mach API 讀目標程序（需先 `just sign-debug apply`，用完 `restore`）；輸出格式見原始碼開頭。
  - `build/experiments/rosetta-probes/callchain <pid> <次數>`
  - `build/experiments/rosetta-probes/memdump <pid> <addr-hex> <len>`
- 狀態：未解（探測工具，無單一結論）。
- 對應：無。
