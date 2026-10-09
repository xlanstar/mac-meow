# 已知問題

`README.md` 的「已知問題」只列出玩家看得到的現象，每項一行；細節都寫在這份文件。每個問題依序寫：症狀、暫時解法、原因、狀態。已修好問題的根因與證據放在 [technical-notes.md](technical-notes.md)，這裡只附連結，不重複內容。

## 1. 人多的地方很卡

- 症狀：頻道 1 的城鎮這類人多的地方，畫面上的玩家和特效越多就越卡；人少的頻道和地圖都很順。
- 暫時解法：避開人多的頻道和地圖，並在遊戲設定裡減少其他玩家的特效。
- 原因：遊戲的防護機制（Themida 虛擬機）在 Rosetta 2 上效能很差。根因與量測數據見 [technical-notes.md](technical-notes.md) 第 9 節。
- 狀態：未解決。要根治必須改動遊戲的記憶體，違反本專案「不修改遊戲」的原則，所以不採用。

## 2. 按住 Command 再按 A／Z／X／C／V，會變成 Ctrl

- 症狀：遊戲裡 Command 鍵等同 Alt（楓之谷預設是跳躍）。如果先按住 Command 再按 A、Z、X、C 或 V，遊戲收到的會是 **Ctrl**＋該字母（楓之谷預設 Ctrl 是攻擊），而且 Alt 會被當成放開後又按了一下。先按字母、再按 Command 則一切正常，所以看起來像是「有時候」才會發生。
- 暫時解法：按住 Command 時不要按這五個鍵。可以在遊戲的鍵盤設定裡，把常用的技能從 A／Z／X／C／V 移到別的鍵，或是把跳躍改到其他鍵。
- 原因：CrossOver 在 Wine 的 Mac 驅動程式（`winemac.drv`）裡加了一段修改（原始碼標記為 `CrossOver Hack 10912: Mac Edit menu`），上游 Wine 沒有這段程式碼，遊戲也沒有問題。以下以 CrossOver 26.3.0 原始碼為準：
  1. `macdrv_main.c` 的預設值是 `mac_edit_menu = MAC_EDIT_MENU_BY_KEY`。`cocoa_app.m` 依此在選單列加入「Edit」選單：Undo ⌘Z、Cut ⌘X、Copy ⌘C、Paste ⌘V、Select All ⌘A（Delete 沒有快捷鍵）。
  2. 按下帶有 Command 的按鍵時，macOS 的 `NSApplication` 會先拿去比對選單快捷鍵。比對成功就會呼叫 `-[WineWindow selectAll:]` 這類方法，再進入 `sendEditMenuCommand:`，這個按鍵事件不會再送到 `keyDown:`。
  3. `keyboard.c` 的 `macdrv_edit_menu_command` 會模擬一串按鍵送給 Windows 程式：放開 Alt → 按下並放開 Alt（避免焦點跑到選單列）→ 按下 Ctrl → 按下並放開字母 → 放開 Ctrl。
  4. `sendEditMenuCommand:` 也會刻意把 Command 標記成沒有按下。原始碼註解寫明這是為了讓放開 Command 時不會選取選單列。
  5. 只有在字母的按下事件帶有 Command 時才會被當成快捷鍵，所以「先按 Command 再按字母」才會觸發。
- 驗證：Cyder engine `CX26.3.0-W11-Cyder012` 的 `winemac.so` 裡有 `selectAll:`、`sendEditMenuCommand:` 等符號；Cyder bottle 裡沒有設定 `EditMenu`，所以使用預設的 `key` 模式。以上是讀原始碼得到的結論，還沒有用 `WINEDEBUG=+key` 實際錄下按鍵順序來確認。
- 可能的修正：`EditMenu` 設成 `key` 或 `message` 以外的值，這個功能就會關閉。關閉後，⌘A 會照常以 Alt+A 送給遊戲。可以只對楓之谷設定：`HKCU\Software\Wine\AppDefaults\MapleStory.exe\Mac Driver` 的 `EditMenu="n"`。這個值在程序啟動時讀取，設定後要重開遊戲才會生效。如果要實作，必須遵守 `AGENTS.md` 規則 4：保留原值、提供還原、由 `uninstall.sh` 呼叫，並列入 [architecture.md](architecture.md)。
- 狀態：未修正。

## 3. 出現「不正確的版本」

- 症狀：伺服器拒絕連線，顯示「不正確的版本」。
- 暫時解法：把符合私服版本要求的 `MapleStory.exe`（版本見 `README.md` 的系統需求）放回遊戲資料夾。
- 原因：官方 `Patcher.exe` 被觸發後，會把 `MapleStory.exe` 更新成官方最新版。是誰觸發的還沒查明，見 [technical-notes.md](technical-notes.md) 的「其他觀察」。
- 狀態：只發生過一次，之後沒有再出現。

## 4. macOS 28 以後可能無法執行

- 症狀：目前還不會發生，這是預期中的風險。
- 暫時解法：在本專案確認相容之前，先不要升級到 macOS 28。
- 原因：Cyder 的 Wine 是 Intel（x86_64）版本，必須透過 Rosetta 2 執行。Apple 已經[公告](https://support.apple.com/zh-tw/102527) macOS 27 是最後一個完整支援 Rosetta 2 的版本，macOS 28 起只保留給部分舊遊戲。會受影響的元件見 [architecture.md](architecture.md) 的「外部變動時要更新的地方」。
- 狀態：等 macOS 28 推出後再驗證。

## 5. 出現「Intel 架構的 App 未來將無法執行」通知

- 症狀：macOS 26.4 以後，啟動 Cyder 的遊戲時可能會跳出這個通知。
- 暫時解法：在 macOS 27 以前不影響遊戲，直接關閉通知即可。
- 原因：與第 4 項相同，macOS 正在逐步淘汰 Rosetta 2。
- 狀態：不需要處理。

## 6. Cyder 更新後無法啟動

- 症狀：App 顯示修補拒絕套用，遊戲無法啟動。
- 暫時解法：回報 issue，或等待本專案更新。
- 原因：App 每次啟動都會重新套用修補。預先建置的 DLL 只能用在建置時的 CrossOver 版本上，如果新版 Cyder 的 Wine 版本差太多，`patch-cyder-dlls.sh` 會拒絕套用。要更新哪些地方見 [architecture.md](architecture.md) 的「外部變動時要更新的地方」。
- 狀態：每次 Cyder 換新的 CrossOver 版本時都要重建 DLL。
