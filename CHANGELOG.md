# Changelog

User-visible changes, newest first: new or changed sites and features, fixes.
List each change under `## Unreleased` as it lands

## Unreleased

- 改以 `.dmg` 發佈：開啟後的視窗有圖解說明，把 `MacMeow.app` 拖到「應用程式」即可安裝，不必再解壓縮 zip
- `MacMeow.app` 新增「回報問題」：在 App 內填寫後開啟已填好內容的 GitHub issue，並自動產生隱藏個人資訊的診斷檔；啟動失敗時可直接「回報此問題」
- 新增 `scripts/report.sh`：輸出可貼到 issue 的環境資訊，或打包診斷檔
- 已知問題：按住 Command 再按 A／Z／X／C／V 會變成 Ctrl（見 docs/known-issues.md）
- 修正 `MacMeow.app` 展開「詳細記錄」時，記錄面板在淡入過程中與上方卡片重疊
- `MacMeow.app` 視窗背景與主要按鈕改為單色，展開或收合「詳細記錄」時背景不再閃爍
- `MacMeow.app` 移除設定視窗：同步機制改在首頁獨立的「Wine 設定」區塊切換
- `MacMeow.app` 精簡首頁：移除標題下的版本說明與狀態卡片的說明文字，連線通道進度條改為填滿整個寬度
- 關閉遊戲後自動關閉登入器、HostShield 等背景程式，Wine 也會完整結束，不必再按「全部關閉」；不影響其他 Cyder 遊戲（`AUTO_CLOSE=0` 可停用）
- 自動收尾與「全部關閉」會一併結束 Cyder 每次啟動後遺留的背景程序
- `MacMeow.app` 的「Wine 設定」新增「遊戲關閉時自動收尾」開關；選單新增「遊戲 → 顯示登入器」（⌘L）

## 0.1.0 — 2026-10-09

首次釋出：可在 Apple Silicon Mac 以 Cyder 執行貓貓谷原版登入流程並進入遊戲，不修改任何遊戲或登入器檔案。

- `MacMeow.app`：原生 SwiftUI 視窗，含環境檢查清單、啟動進度、連線通道狀態、詳細記錄，以及「開始遊戲」「全部關閉」「重新啟動」；需要 macOS 13 以上
- `MacMeow.app` 設定：遊戲資料夾、同步機制
- 第一次啟動自動完成：選擇遊戲資料夾、管理員授權設定本機網路、套用 Cyder 修補、安裝 VB6 執行環境、調整 Cyder 設定
- 網路：lo0 加入 HostShield 通道位址與 202.80.104.28，並以 LaunchDaemon 開機自動套用
- Cyder wineserver：關閉 bind 127.x → 127.0.0.1 改寫
- Wine 修補：`wsock32!recv` 獨立化（修正遊戲凍結）、advapi32 CSP 常駐（修正 rsaenh 反覆載入）；套用前比對 `SHA256SUMS`
- Cyder 設定：zh_TW、DXMT、MSync
- 啟動時等到 4 個 HostShield 通道都開始監聽才回報成功
- 套用修補時若有其他 Cyder 遊戲在執行，提示先關閉，不會自動關閉 Wine
- 指令介面：`play.sh` 啟動、`play.sh status` 列出各位址的監聽 port 數與程序、`play.sh stop` 關閉 Cyder 內所有 Windows 程式
- `uninstall.sh` 還原 Cyder engine 修補、移除本機網路位址與 LaunchDaemon、App 設定與記錄；若 Cyder 已更新 engine，不會把舊檔蓋回新版
- Releases 的 `MacMeow.app` 以 Developer ID 簽章並經 Apple 公證，下載後可直接開啟
- 已知問題：人多的地方卡頓（Themida × Rosetta SMC，見 docs/technical-notes.md）
