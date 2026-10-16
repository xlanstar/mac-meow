<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/images/readme-hero-dark.jpg">
  <img src="docs/images/readme-hero-light.jpg" alt="MacMeow 的選單列選單：遊戲執行中，連線通道與環境檢查全部就緒">
</picture>

---

[![最新版本](https://img.shields.io/github/v/release/xlanstar/mac-meow?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC)](https://github.com/xlanstar/mac-meow/releases/latest)

讓 Mac **不用虛擬機**，透過 [Cyder](https://github.com/dspp779/CyderBits)（Wine）執行 [貓貓谷](https://meowms.net)。

原則：**不破解、不修改** 遊戲與登入器檔案，本專案只在 macOS／Wine 端補上與 Windows 的差異（本機網路位址、Wine 修正、Cyder 設定）。

## 功能特色

- **一鍵開始遊戲**：`MacMeow.app` 常駐在選單列，從貓掌圖示選「開始遊戲」就會自動完成所有設定並啟動認證器與登入器，「環境檢查」顯示每一項的狀態。
- **效能優化**：在 Wine 端修正進入遊戲世界後的低 FPS、預設開啟 MSync 與 D3DMetal，並減輕打怪、撿道具時的音效卡頓。

## 系統需求

- Apple Silicon Mac，macOS 13 以上；需安裝 Rosetta 2（第一次執行 x86 程式時系統會提示）
- [Cyder](https://github.com/dspp779/CyderBits/releases)（已在 0.13.2、engine `CX26.3.0-W11-Cyder012` 測試）
- 楓之谷遊戲資料夾：依 [官方文件](https://meowms.net/guide.php) 準備

## 安裝

1. **安裝 Cyder**：從 [Cyder Releases](https://github.com/dspp779/CyderBits/releases) 下載，把 `Cyder.app` 拖到「應用程式」。
2. **安裝 MacMeow**，以下擇一：
   - **Homebrew**（推薦）

     ```sh
     brew install --cask xlanstar/tap/macmeow
     ```

   - **手動下載**：從 [最新版 Release](https://github.com/xlanstar/mac-meow/releases/latest) 下載 dmg，開啟後把 `MacMeow.app` 拖到「應用程式」。

3. 從「應用程式」開啟 `MacMeow.app`。App 經過 Apple 公證，第一次開啟時按「打開」即可。App 沒有視窗與 Dock 圖示，開啟後在螢幕右上角的選單列出現貓掌圖示，所有功能都在它的選單裡；看不到圖示時，可能被瀏海或其他圖示擋住，按住 ⌘ 把其他選單列圖示拖開即可。

## 使用方式

### 第一次開始遊戲

在貓掌選單選「開始遊戲」後，App 會依序引導完成以下設定，之後就不需要再做：

1. **選擇遊戲資料夾**：選擇內含 `MapleStory.exe` 與貓貓谷登入器檔案的資料夾（放在 `~/Games/MapleStory` 會自動找到）。
2. **建立 Windows 環境**：沒用過 Cyder 時，App 會開啟 Cyder 讓它初始化，約 1–3 分鐘。
3. **設定本機網路位址**：輸入一次電腦密碼，加入連線需要的本機位址，並設定開機時自動套用。
4. **安裝與啟動**：套用 Wine 修補、安裝 VB6 執行環境（約 1–2 分鐘），再啟動認證器與登入器。

貓掌選單的「環境檢查」會顯示每一項的狀態；某一步失敗時會跳出錯誤訊息，可以選「開啟記錄檔」或「回報此問題…」。

### 平常使用

在貓掌選單選「開始遊戲」（App 沒在執行時先開啟 `MacMeow.app`），等登入器出現後照平常方式登入。

- **關閉遊戲**：直接關閉遊戲即可，登入器、HostShield 等背景程式會在幾秒內自動關閉，其他 Cyder 遊戲不受影響。
- **全部關閉／重新啟動**：在貓掌選單選擇；會一併關閉 Cyder 內其他正在執行的遊戲。
- **叫出登入器**：遊戲執行時登入器會自動縮到最小，在貓掌選單選「顯示登入器」叫出來。
- **結束 App**：在貓掌選單選「結束貓貓谷 for Mac」。
- **遊戲設定**：在貓掌選單的「遊戲設定」調整，下次「開始遊戲」時套用（Cyder 正在執行時要全部關閉後才會生效）：
  - **同步機制**：MSync（建議）、ESync 或關閉。
  - **圖形後端**：預設 D3DMetal，需要 macOS 14 以上並安裝 CrossOver 或在 Cyder 設定安裝 GPTK；也可改選 DXMT，需要 macOS 15 以上。無法使用時依序自動改用 DXMT、DXVK 或 Wine 內建的 wined3d。
  - **FPS 上限**：60、120、144 或不限制（預設，最高為螢幕更新率）；wined3d 不適用。
  - **顯示效能 HUD**：在遊戲畫面顯示 FPS。
  - **遊戲關閉時自動收尾**：預設開啟；此選項關閉時，遊戲結束後登入器與背景程式會留著。
- **記錄檔**：在 `~/Library/Logs/MacMeow/launcher.log`，也可以在貓掌選單選「說明 → 開啟記錄檔」查看。

### 更新

App 會自動檢查新版本，有新版時貓掌選單會出現「更新到 x.y.z」；也可以從貓掌選單「貓貓谷 for Mac → 檢查更新…」手動檢查。

- **手動下載安裝的**：選「更新到 x.y.z」，App 會自動下載、安裝並重新開啟，設定會保留；網路中斷時會等待並從中斷處繼續下載。
- **用 Homebrew 安裝的**：選「更新到 x.y.z…」後按「複製指令」，貼到「終端機」執行 `brew upgrade --cask macmeow`。

## 移除

- **手動下載安裝的**：在貓掌選單選「貓貓谷 for Mac → 解除安裝…」。
- **用 Homebrew 安裝的**：在「終端機」執行 `brew uninstall --cask macmeow`。

兩種方式都會還原 Cyder engine 的修補與 Cyder 設定的原值、加回遊戲資料夾的下載隔離標記、移除本機網路位址與開機設定（需要密碼），並刪除 App 的設定與記錄。遊戲、Cyder 與其設定不會被刪除。

## 已知問題

原因和暫時解法見 [docs/known-issues.md](docs/known-issues.md)。

- **人多的地方很卡**：避開人多的頻道和地圖。
- **按住 Command 再按 A／Z／X／C／V 會變成 Ctrl**：按住 Command 時不要按這五個鍵。
- **「不正確的版本」**：把私服要求版本的 `MapleStory.exe` 放回遊戲資料夾。
- **macOS 28 以後可能無法執行**：在本專案確認相容之前，先不要升級。
- **出現「Intel 架構的 App 未來將無法執行」通知**：macOS 27（含）以前不影響遊戲，直接關閉即可。
- **Cyder 更新後無法啟動**：請回報 issue，或等待本專案更新。

## 回報問題

遇到問題請 [建立 GitHub Issue](https://github.com/xlanstar/mac-meow/issues/new?template=bug_report.yml) 回報。

## 開發

本專案以 AI agent 開發。開發規範見 [AGENTS.md](AGENTS.md)，技術文件在 [docs/](docs/)。

## 授權

本專案腳本與工具為 MIT License；`patches/` 內的 Wine 修補與 DLL 為 LGPL-2.1-or-later。

> **免責聲明**：本專案與 Nexon、遊戲橘子、貓貓谷、Cyder 皆無關。私服的使用風險（帳號、合法性）請自行評估。專案不包含任何遊戲或登入器檔案。HostShield 每次啟動會下載並執行私服提供的遠端程式碼，這是原版行為，在 Windows 上也一樣。
