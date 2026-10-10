#!/bin/bash
# 檢查開發環境：Xcode Command Line Tools 與 Brewfile 內的工具。全部可用時 exit 0，否則列出缺少項目並 exit 1。
#
# 用法：bash tools/doctor.sh
set -uo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

missing=()

# check <名稱> <指令...>：指令成功即可用。
check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    ok "$name"
  else
    echo "  ✗ ${name}"
    missing+=("$name")
  fi
}

# 先確認 developer dir，避免 xcrun 在沒有 CLT 時跳出安裝對話框
if xcode-select -p >/dev/null 2>&1; then
  ok "Xcode Command Line Tools"
  check swiftc xcrun --find swiftc
  check clang xcrun --find clang
else
  echo "  ✗ Xcode Command Line Tools（xcode-select --install）"
  missing+=("Xcode Command Line Tools")
fi

check brew command -v brew
llvm_paths 2>/dev/null || true # 只取 LLVM_BIN／LLD_BIN／BISON_BIN
while IFS= read -r line; do
  [[ "$line" =~ ^brew[[:space:]]+\"([^\"]+)\" ]] || continue
  f="${BASH_REMATCH[1]}"
  case "$f" in
    llvm) bin="$LLVM_BIN/clang" ;; # keg-only，不在 PATH
    lld) bin="$LLD_BIN/lld-link" ;;
    bison) bin="$BISON_BIN/bison" ;;
    mingw-w64) bin=x86_64-w64-mingw32-gcc ;;
    *) bin="$f" ;;
  esac
  check "$f" command -v "$bin"
done <"$ROOT/Brewfile"

if ((${#missing[@]})); then
  echo "缺少：${missing[*]}（${BREW_HINT}）" >&2
  exit 1
fi
echo "開發環境完整"
