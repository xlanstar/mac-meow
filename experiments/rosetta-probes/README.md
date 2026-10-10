# rosetta-probes

- 問題：臨時探測 Rosetta 下執行中的程序：CPU 最高的執行緒在跑哪條呼叫鏈、某位址有哪些字串。
- 做法：以 Mach API 讀目標程序（需先 `bash tools/diag/sign-debug.sh apply`，用完 `restore`）。
  - `build/experiments/rosetta-probes/callchain <pid> <次數>`：取樣 CPU 最高的執行緒（翻譯碼中 `x4=rsp`），只輸出前一條指令是 `call` 的返回位址，每行一個樣本。
  - `build/experiments/rosetta-probes/memdump <pid> <addr-hex> <len>`：輸出讀到的位元組數與可列印字串（≥6 字元）。
- 狀態：未解（探測工具，無單一結論）。
- 對應：無。
