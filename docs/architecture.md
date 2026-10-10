# 架構

貓貓谷在 macOS 上的執行鏈與連線路徑，以及 repo 各資料夾的分工；細節在各資料夾連到的文件。

## 執行鏈與連線路徑

```
認證器.exe (VB6) ──► HostShield.exe ×4（監聽 127.x.x.1:37601-37630 → WebSocket 通道到伺服器）
              └──► 貓貓TMS登入器.exe ──► MapleStory.exe（+ BlackCipher/NGS、NxOverlay）

MapleStory.exe → 202.80.104.28:37629（lo0 alias）
              → 登入器 0.0.0.0:37629（轉發）
              → 127.145.37.1:37629（HostShield）
              → WebSocket → 伺服器
```

- 位址與 port 見 `common.sh` 的 `HOSTSHIELD_IPS`、`HOSTSHIELD_PORTS`、`GAME_ALIAS_IP`。
- 執行環境：Cyder（CrossOver 版 Wine，x86_64 經 Rosetta 2）；測試過的 CrossOver 基底見 [patches/SOURCES.md](../patches/SOURCES.md)。
- `MapleStory.exe` 是 PE32+ x86-64，與台服官方相同。
- 讓這條鏈在 Wine 上動起來的每個修補（根因與證據）見 [fixes.md](fixes.md)；這些修補改動的 repo 以外狀態見 [external-state.md](external-state.md)。

## 資料夾

- `scripts/`：使用者流程，打包進 `MacMeow.app`；各腳本見 [scripts.md](scripts.md)，遊戲設定與環境變數見 [settings.md](settings.md)。
- `app/`：`MacMeow.app`（SwiftUI）與 dmg 的建置；見 [app.md](app.md)。
- `tools/`：開發用。共用函式在 `tools/lib.sh`（建立在 `scripts/lib/common.sh` 之上），入口腳本依用途分在：
  - `tools/diag/`：一般的 Wine × Rosetta 診斷，見 [debugging.md](debugging.md#診斷工具)。
  - `tools/game/`：本專案專屬的啟動與自動操作，見 [debugging.md](debugging.md#診斷工具)。
  - `tools/dev/`：建置、測試、環境檢查，見 [development.md](development.md)。
  - `tools/release/`：發佈，見 [release.md](release.md)。
  - `tools/src/<name>/`：開發工具的原始碼。診斷工具由 `tools/dev/build.sh` 建置，`repo-images/` 是 `tools/dev/repo-images.sh` 的 HTML 範本。
- `patches/`：`*.patch` 是 Wine 原始碼修補，`bin/` 是預先建置的 DLL 與 `SHA256SUMS`；重建見 [wine-patches.md](wine-patches.md)，來源與授權見 [patches/SOURCES.md](../patches/SOURCES.md)。
- `packaging/homebrew/`：Homebrew cask 範本，見 [homebrew.md](homebrew.md)。
- `experiments/`：一次性實驗，見 [experiments/README.md](../experiments/README.md)。
- `.github/`：發佈 workflow、Dependabot（見 [ci.md](ci.md)）與 issue 表單（`ISSUE_TEMPLATE/bug_report.yml`，App 的「回報問題」預先填入，見 [app.md](app.md#功能)）。
- `docs/`：本文件與其他開發文件（各文件的分工見 `AGENTS.md`）；其中 [known-issues.md](known-issues.md) 是寫給使用者、由 App 直接開啟的頁面。`images/` 是 README 用的圖片（見 [repo-images.md](repo-images.md)）。
