<!--
維護說明（GitHub 不顯示）

- 這個檔案不可改名或搬移：App 直接開這個路徑（app/Sources/Services/AppPaths.swift 的 AppPaths.knownIssues）。要改路徑時，先發佈指向新位置的 App 版本，並保留舊檔一段時間。
- 「## N. …」標題文字不要改：issue 留言與其他文件連到這些標題的錨點。
- 處理流程：
  1. 使用者回報後是 open issue（未驗證）。
  2. 驗證後在這裡新增一節，依序寫：症狀、暫時解法、原因、狀態；並在 README.md 的「已知問題」加一行玩家看得到的摘要。在 issue 留言附上該節連結，再關閉 issue。
  3. 修好後把狀態改成「X.Y.Z 已修正，請更新」，幾個版本後刪除該節與 README.md 的摘要。
  4. 根因與證據需要保留時才寫進 docs/fixes.md（不是每個問題都要），這裡只用白話說明並附連結，不重複內容。
-->

# 已知問題

這裡列出已驗證的問題與暫時解法；GitHub 上 open 的 issue 是使用者回報、尚未驗證的問題。

## 1. 人多的地方很卡

- 症狀：頻道 1 的城鎮這類人多的地方，畫面上的玩家和特效越多就越卡；人少的頻道和地圖都很順。
- 暫時解法：避開人多的頻道和地圖，並在遊戲內的設定裡減少其他玩家的特效。
- 原因：遊戲的防護機制（Themida 虛擬機）在 Rosetta 2 上效能很差。根因與量測數據見 [fixes.md](fixes.md#9-人多的地方很卡themida-vm--rosetta-smc未解) 第 9 節。
- 狀態：未解決。要根治必須改動遊戲的記憶體，違反本專案「不修改遊戲」的原則，所以不採用。

## 2. 按住 Command 再按 A／Z／X／C／V，會變成 Ctrl

- 症狀：遊戲裡 Command 鍵等同 Alt（楓之谷預設是跳躍）。如果先按住 Command 再按 A、Z、X、C 或 V，遊戲收到的會是 **Ctrl**＋該字母（楓之谷預設 Ctrl 是攻擊），而且 Alt 會被當成放開後又按了一下。先按字母、再按 Command 則一切正常，所以看起來像是「有時候」才會發生。
- 暫時解法：按住 Command 時不要按這五個鍵。可以在遊戲內的鍵盤設定裡，把常用的技能從 A／Z／X／C／V 移到別的鍵，或是把跳躍改到其他鍵。
- 原因：Cyder 使用的 CrossOver 版 Wine 在選單列加了「Edit」選單，⌘A、⌘Z、⌘X、⌘C、⌘V 是它的快捷鍵（全選、還原、剪下、拷貝、貼上）。先按住 Command 再按這些字母時，macOS 會先把按鍵當成選單快捷鍵，Wine 再改用 Ctrl＋字母送給遊戲。這不是遊戲的問題，技術細節見 [fixes.md](fixes.md#14-按住-command-再按-azxcv-變成-ctrlcrossover-的-edit-選單) 第 14 節。
- 狀態：未修正。

## 3. 出現「不正確的版本」

- 症狀：伺服器拒絕連線，顯示「不正確的版本」。
- 暫時解法：依 [官方文件](https://meowms.net/guide.php) 重新取得私服要求版本的 `MapleStory.exe`，放回遊戲資料夾。
- 原因：官方 `Patcher.exe` 被觸發後，會把 `MapleStory.exe` 更新成官方最新版。是誰觸發的還沒查明，見 [fixes.md](fixes.md#其他觀察) 的「其他觀察」。
- 狀態：只發生過一次，之後沒有再出現。

## 4. macOS 28 以後可能無法執行

- 症狀：目前還不會發生，這是預期中的風險。
- 暫時解法：在本專案確認相容之前，先不要升級到 macOS 28。
- 原因：Cyder 的 Wine 是 Intel（x86_64）版本，必須透過 Rosetta 2 執行。Apple 已經[公告](https://support.apple.com/zh-tw/102527) macOS 27 是最後一個完整支援 Rosetta 2 的版本，macOS 28 起只保留給「仰賴 Intel 框架、已不再維護的舊遊戲」，沒有說明是否包含 Wine。會受影響的元件見 [upstream-changes.md](upstream-changes.md)。
- 狀態：等 macOS 28 推出後再驗證。

## 5. 出現「Intel 架構的 App 未來將無法執行」通知

- 症狀：macOS 26.4 以後，啟動 Cyder 的遊戲時可能會跳出這個通知。
- 暫時解法：macOS 27（含）以前不影響遊戲，直接關閉通知即可。
- 原因：與第 4 項相同，macOS 正在逐步淘汰 Rosetta 2。
- 狀態：不需要處理。

## 6. Cyder 更新後無法啟動

- 症狀：App 顯示修補拒絕套用，遊戲無法啟動。
- 暫時解法：回報 issue，或等待本專案更新。
- 原因：每次按「開始遊戲」時，`play.sh` 都會檢查並套用修補。預先建置的 DLL 只能用在建置時的 CrossOver 版本上，新版 Cyder 的 CrossOver 版本只要不同，`patch-cyder-dlls.sh` 就會拒絕套用。要更新哪些地方見 [upstream-changes.md](upstream-changes.md)。
- 狀態：每次 Cyder 換新的 CrossOver 版本時都要重建 DLL。
