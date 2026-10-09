#!/bin/bash
# 編譯並執行 App 核心邏輯（app/Sources/Core）的單元測試。只需要 Command Line Tools（不用 XCTest、SPM、Xcode）。
# 測試原始碼在 app/Tests/（main.swift 依序呼叫各檔案的 test 函式），執行檔輸出到 build/tests/（不污染原始碼目錄）。
#
# 用法：bash tools/test-app.sh
#   全部通過時印出檢查數並以 0 結束；失敗的檢查（檔案:行號）印到 stderr，以 1 結束。
#   tools/release.sh check 也會執行。
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

OUT="$ROOT/build/tests"
mkdir -p "$OUT"

app_sources Core
TESTS=()
while IFS= read -r f; do TESTS+=("$f"); done < <(find "$ROOT/app/Tests" -name '*.swift' | sort)

swiftc -swift-version 5 -module-name MacMeowTests -target "$APP_SWIFT_TARGET" \
  -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
  -o "$OUT/core-tests" ${APP_SOURCES[@]+"${APP_SOURCES[@]}"} ${TESTS[@]+"${TESTS[@]}"}
"$OUT/core-tests"
