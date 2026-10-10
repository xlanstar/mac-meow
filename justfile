# 開發工具的統一入口（brew bundle 已含 just）。只轉呼叫 tools/、experiments/ 的腳本並原樣傳遞參數；
# 用法與副作用見各腳本開頭，--list 看不出的注意事項見 docs/debugging.md。腳本仍可直接執行（CI、prek 直接呼叫）。

set positional-arguments

# 列出所有指令
_default:
    @just --list --unsorted

# ---------- 診斷（tools/diag） ----------

# 擷取目標程序堆疊：[--exe 名稱] [--pid pid]... mach|prof|lldb|wine [參數]
[group('diag')]
stack *args:
    @bash tools/diag/stack.sh "$@"

# engine wine 的除錯簽章（get-task-allow）：status|apply|restore
[group('diag')]
sign-debug *args:
    @bash tools/diag/sign-debug.sh "$@"

# bottle 內 Wine 視窗操作：[--here] list|click|sclick|shot|fg|key ...
[group('diag')]
wgui *args:
    @bash tools/diag/wgui.sh "$@"

# 擷取 Wine 視窗：[輸出檔] [視窗標題]
[group('diag')]
shot *args:
    @bash tools/diag/shot.sh "$@"

# ---------- 遊戲（tools/game） ----------

# 不經 Cyder.app 啟動完整流程：[plain|trace|relay|virtual|server]
[group('game')]
run-game *args:
    @bash tools/game/run-game.sh "$@"

# 自動點登入器的「開始遊戲」：[--here]
[group('game')]
auto-start *args:
    @bash tools/game/auto-start.sh "$@"

# ---------- 開發（tools/dev） ----------

# 建置 tools/src 的診斷工具：[目標...]
[group('dev')]
build *args:
    @bash tools/dev/build.sh "$@"

# App Core 單元測試
[group('dev')]
test *args:
    @bash tools/dev/test-app.sh "$@"

# 檢查開發環境（Xcode CLT、Brewfile）
[group('dev')]
doctor *args:
    @bash tools/dev/doctor.sh "$@"

# 重建 patches/bin 的修補版 Wine DLL
[group('dev')]
build-wine-dlls *args:
    @bash tools/dev/build-wine-dlls.sh "$@"

# 產生 repo 圖片：[--update-readme] [App 視窗截圖.png]
[group('dev')]
repo-images *args:
    @bash tools/dev/repo-images.sh "$@"

# 檢查 commit 訊息有 body（commit-msg hook）：<commit-msg 檔案>
[group('dev')]
check-commit-body *args:
    @bash tools/dev/check-commit-body.sh "$@"

# 檢查 prek 內建 hook 管不到的規範：<gitignore|justfile|external-state|dlls|usage|release-files|app>...
[group('dev')]
lint *args:
    @bash tools/dev/lint.sh "$@"

# 建置一次性實驗：[實驗...]
[group('dev')]
exp *args:
    @bash experiments/build.sh "$@"

# ---------- 發佈（tools/release） ----------

# 發佈流程：check|prepare|build|publish|ci|draft|release|tap X.Y.Z
[group('release')]
release *args:
    @bash tools/release/release.sh "$@"

# CI 暫時鑰匙圈（只在 GitHub Actions）：setup|cleanup
[group('release')]
ci-keychain *args:
    @bash tools/release/ci-keychain.sh "$@"

# 設定 GitHub Actions Secrets：[--dry-run]
[group('release')]
setup-ci-secrets *args:
    @bash tools/release/setup-ci-secrets.sh "$@"
