# mac-meow：在 Apple Silicon Mac 上玩貓貓谷

[![最新版本](https://img.shields.io/github/v/release/xlanstar/mac-meow?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC)](https://github.com/xlanstar/mac-meow/releases/latest)

**[⬇ 下載最新版 MacMeow.app](https://github.com/xlanstar/mac-meow/releases/latest)**（在頁面下方「Assets」點 `MacMeow-<版本>.dmg`）

讓 Apple Silicon（M 系列）Mac **不用虛擬機**，透過 [Cyder](https://github.com/dspp779/CyderBits)（Wine）執行台版楓之谷私服「貓貓谷」的原版登入流程。

原則：**不破解、不修改** 遊戲與登入器檔案，完整照原本流程執行：

```
認證器.exe ──► HostShield.exe ×4（本機連線通道）
          └──► 貓貓TMS登入器.exe ──► MapleStory.exe
```

本專案只在 macOS／Wine 端補上與 Windows 的差異（本機網路位址、Wine 修正、Cyder 設定）。

> **免責聲明**：本專案與 Nexon、遊戲橘子、貓貓谷、Cyder 皆無關。私服的使用風險（帳號、合法性）請自行評估。專案不包含任何遊戲或登入器檔案。HostShield 每次啟動會下載並執行私服提供的遠端程式碼，這是原版行為，在 Windows 上也一樣。

## 系統需求

- Apple Silicon Mac，macOS 13 以上；需安裝 Rosetta 2（第一次執行 x86 程式時系統會提示）
- [Cyder](https://github.com/dspp779/CyderBits/releases)（已在 0.13.2、engine `CX26.3.0-W11-Cyder012` 測試）
- 楓之谷遊戲資料夾（`MapleStory.exe` 版本需符合伺服器要求，目前為 6.282.4.0），並已把貓貓谷登入器壓縮檔的內容（`認證器.exe`、`貓貓TMS登入器.exe`、`HostShield.exe`、`XCGUI.dll`）解壓縮到遊戲資料夾

## 使用方式（建議：MacMeow.app）

1. 安裝 Cyder：下載後把 `Cyder.app` 拖到「應用程式」，開啟一次讓它建立 Windows 環境。
2. 取得 `MacMeow.app`：
   - 從 [最新版 Release](https://github.com/xlanstar/mac-meow/releases/latest) 下載 `MacMeow-<版本>.dmg`；或
   - 自行建置（需要 Xcode 或 `xcode-select --install`）：`bash app/build-app.sh` → `dist/MacMeow-<版本>.dmg`
3. 雙擊開啟 `.dmg`，在出現的視窗中把 `MacMeow.app` 拖到旁邊的「Applications」（應用程式）資料夾，再從「應用程式」開啟 `MacMeow.app`。
   - Releases 的 App 經過 Apple 公證，第一次開啟時按「打開」即可。
   - 安裝完成後可以在 Finder 側邊欄退出「MacMeow」磁碟，並刪除 `.dmg`。

之後每次只要開啟 `MacMeow.app` 按「開始遊戲」即可。App 視窗會顯示環境檢查清單與連線通道狀態；遊戲執行中可以按「全部關閉」或「重新啟動」（會一併關閉其他 Cyder 遊戲）。同步機制等選項在選單「MacMeow → 設定⋯」。記錄檔在 `~/Library/Logs/MacMeow/launcher.log`，也可以在 App 內展開「詳細記錄」查看。

### 不用 App，改用指令

```sh
sudo bash scripts/setup-loopback.sh install   # 只需一次
GAME_DIR=~/Games/MapleStory bash scripts/play.sh
bash scripts/play.sh status                   # 檢查通道／程序
```

## 移除

```sh
bash scripts/uninstall.sh
```

會還原 Cyder engine 的修補、移除本機網路位址與 LaunchDaemon（需要密碼），以及 App 的設定與記錄。遊戲、Cyder 與其設定不會被刪除。

## 已知問題

- **人多的地方很卡**（例如頻道 1 的城鎮）：遊戲的防護機制在 Rosetta 2 上效能很差，畫面上的玩家／特效越多越卡；人少的頻道與地圖順暢。減輕方式：避開人多的頻道與地圖、在遊戲設定中減少其他玩家特效。
- **「不正確的版本」**：若官方 `Patcher.exe` 被觸發，`MapleStory.exe` 會被更新成官方最新版，伺服器就會拒絕。請把私服要求版本的 `MapleStory.exe` 放回遊戲資料夾。
- **Cyder 更新後無法啟動**：App 每次啟動都會重新套用修補；若新版 Cyder 的 Wine 版本差太多，修補會拒絕套用並顯示訊息，請回報 issue 或等待本專案更新。

## 開發

本專案以 AI agent 開發。開發規範見 [AGENTS.md](AGENTS.md)，技術文件在 [docs/](docs/)。

## 授權

本專案腳本與工具為 MIT License；`patches/` 內的 Wine 修補與 DLL 為 LGPL-2.1-or-later。
