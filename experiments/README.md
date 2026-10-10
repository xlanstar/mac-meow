# 實驗

回答一次性問題的程式；定位見 [AGENTS.md](../AGENTS.md#code-conventions)「Code conventions」；其他資料夾不可依賴實驗（prek 檢查）。

## 規範

- 每個實驗資料夾的 `README.md` 只寫：問題、做法（一句）與執行指令（參數見原始碼開頭）、狀態（結論已記錄／未解）、對應的 [fixes.md](../docs/fixes.md) 編號。結論與數據只寫在 fixes.md。
- 建置：`just exp`；新增實驗見 `experiments/build.sh` 開頭。

## 清單

- [smc-same-page](smc-same-page/)：Rosetta 同頁寫入（SMC）成本（#9）。
- [rsaenh-reload](rsaenh-reload/)：rsaenh.dll 反覆載入／卸載是否卡死（#7）。
- [rosetta-probes](rosetta-probes/)：熱執行緒呼叫鏈取樣、讀記憶體字串。
