# 實驗

回答一次性問題的程式。不保證維護，可用任何第三方工具；`scripts/`、`app/`、`tools/` 不得依賴這裡。

## 規範

- 每個實驗一個資料夾，`README.md` 只寫：問題、做法與執行方式、狀態（結論已記錄／未解）、對應的 [technical-notes](../docs/technical-notes.md) 編號。結論與數據只寫在 technical-notes。
- 建置：`bash experiments/build.sh [實驗...]`（不指定則全部），產物在 `build/experiments/<實驗>/`；新實驗加進 `build.sh` 的 `ALL` 與 `build_one`。Windows 程式用 `tools/lib.sh` 的 `win_exe`。
- 紀錄寫到 `debug/`。

## 清單

- [smc-same-page](smc-same-page/)：Rosetta 同頁寫入（SMC）成本（#9）。
- [rsaenh-reload](rsaenh-reload/)：rsaenh.dll 反覆載入／卸載是否卡死（#7）。
- [rosetta-probes](rosetta-probes/)：熱執行緒呼叫鏈取樣、讀記憶體字串。
