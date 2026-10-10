# 開發

開發環境、建置與測試、測試 `uninstall.sh` 與提交前檢查。各資料夾的分工見 [architecture.md](architecture.md#資料夾)，App 原始碼分層與擴充方式見 [app.md](app.md)；診斷工具見 [debugging.md](debugging.md)，重建 Wine DLL 見 [wine-patches.md](wine-patches.md)，repo 圖片見 [repo-images.md](repo-images.md)，發佈見 [release.md](release.md)。

## 環境

- Apple Silicon Mac、Rosetta 2、Cyder。
- Xcode 或 Command Line Tools（`swiftc`、`/usr/bin/clang`、`iconutil`）：建置 `MacMeow.app` 與 `tools/src/` 的 macOS 工具。
- 開發工具：在 repo 根目錄執行 `brew bundle`（清單在 `Brewfile`），`just doctor` 檢查是否齊全。

## 建置與測試

```sh
bash app/build-app.sh                              # App 與 dmg（簽章與 Finder 排版見 app.md#建置與-dmg）
open dist/MacMeow.app                              # 開啟 App；記錄檔見 AppPaths.logFile（選單「遊戲 → 開啟記錄檔」）
just test
bash scripts/play.sh status --porcelain            # App 讀取的狀態（key=value）
GAME_DIR=~/Games/MapleStory bash scripts/play.sh   # 直接跑使用者流程
bash scripts/play.sh status                        # 通道／程序狀態
bash scripts/patch-cyder-dlls.sh check
bash scripts/session.sh status                     # 遊戲階段監看（記錄檔見 session.sh 的 LOG_FILE）
```

## 測試 `uninstall.sh`

不要直接執行：除了 `brew-command` 與 `stage`，各子指令都會真的還原修補、移除迴路位址或刪除 App 設定。複製到暫存資料夾（與 cask 從 Caskroom 執行時相同，`scripts/` 單獨存在、沒有 App）、把有副作用的函式換成 echo 後再跑；`cask` 的判斷（見 [homebrew.md](homebrew.md#安裝與移除)）可以放在假的 brew 程序底下驗證（perl 改 `$0` 模擬 `brew.rb <子指令>` 的命令列）：

```sh
T="$(mktemp -d)" && mkdir -p "$T/scripts" && cp -R scripts/lib "$T/scripts/"
sed 's/^  cmd_all$/  echo WOULD_UNINSTALL/' scripts/uninstall.sh >"$T/scripts/uninstall.sh"
for sub in upgrade reinstall install uninstall; do
  perl -e '$0 = "/x/ruby /opt/homebrew/Library/Homebrew/brew.rb '"$sub"' --cask macmeow"; system("/usr/bin/env", "/bin/bash", "'"$T"'/scripts/uninstall.sh", "cask")'
done # 前三個應輸出「保留 MacMeow 的修補與設定」，uninstall 輸出 WOULD_UNINSTALL
```

## 提交前檢查（prek）

```sh
prek install
prek run -a
prek update
```

Hook 清單見 `prek.toml`；各工具的設定檔：`.editorconfig`（shfmt）、`.shellcheckrc`、`.swift-format`、`ruff.toml`、`_typos.toml`、`committed.toml`（commit 訊息）。shfmt、`swift format`、ruff 會直接改寫檔案，改完重新 `git add` 再提交。
