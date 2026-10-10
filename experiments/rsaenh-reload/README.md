# rsaenh-reload

- 問題：`rsaenh.dll` 在同一位址反覆卸載再映射，是否會在 Wine／Rosetta 下卡死。
- 做法：背景執行緒不停 `LoadLibrary`／`FreeLibrary`，主執行緒載入 300 次並查 `CPAcquireContext`，印出經過毫秒數。在 shared bottle 執行（會啟動 Wine）：`bash -c 'source tools/lib.sh && run_wine build/experiments/rsaenh-reload/reloadtest.exe'`。
- 狀態：未解；推定已由 `advapi32-pin-csp.patch`（CSP 常駐，不再卸載）避開，未再驗證。
- 對應：technical-notes #7。
