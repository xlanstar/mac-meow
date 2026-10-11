# net-blip

- 問題：Wi-Fi 瞬斷（本機 IP 被移除後恢復）或換網路時，TCP 連線送資料會收到哪個錯誤、連線能否存活；Wine 的 Winsock 與原生是否不同。
- 做法：原生與 Wine 內各一條 HTTP keep-alive 連線持續送請求，期間關閉 Wi-Fi 數秒再打開（`run.sh` 開頭）。
  - `just exp net-blip`
  - `bash experiments/net-blip/run.sh`（會中斷整台 Mac 的網路；先關閉遊戲）
- 狀態：結論已記錄。
- 對應：fixes #15。
