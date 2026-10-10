#!/bin/bash
# 建置 tools/src/ 下的診斷工具，產物放在 build/tools/（不污染原始碼目錄）。
#
# 用法：bash tools/dev/build.sh [目標...]   （不指定則建置全部；個別失敗不中斷，最後回報）
#
# macOS 工具（只需 Xcode clang）：
#   machstack                原生 arm64，以 Mach API 讀 Rosetta 程序（src/machstack）
#   symx86                   x86_64，在 Rosetta 下以 dladdr 解析 shared cache 符號
# Windows 工具（Homebrew mingw-w64，lib.sh 的 win_exe）：
#   wthreads.exe wgui.exe recvcheck.exe
set -uo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

SRC="$ROOT/tools/src"
ALL=(machstack symx86 wthreads.exe wgui.exe recvcheck.exe)

# mac_tool <名稱> <來源目錄> [clang 參數...]
mac_tool() {
  local name="$1" dir="$2"
  shift 2
  /usr/bin/clang -O1 "$@" -o "$TOOLS_BIN/$name" "$SRC/$dir/$name.c"
}

build_one() {
  case "$1" in
    machstack) mac_tool machstack machstack -g -Wall ;;
    symx86) mac_tool symx86 machstack -arch x86_64 ;;
    wthreads.exe) win_exe "$SRC/wthreads/wthreads.c" "$TOOLS_BIN/wthreads.exe" -lntdll ;;
    wgui.exe) win_exe "$SRC/wgui/wgui.c" "$TOOLS_BIN/wgui.exe" -lgdi32 ;;
    recvcheck.exe) win_exe "$SRC/recvcheck/recvcheck.c" "$TOOLS_BIN/recvcheck.exe" -lws2_32 ;;
    *)
      echo "未知目標：$1（可用：${ALL[*]}）" >&2
      return 1
      ;;
  esac
}

(($#)) || set -- "${ALL[@]}"
mkdir -p "$TOOLS_BIN"
failed=()
for t in "$@"; do
  if build_one "$t"; then echo "完成：build/tools/$t"; else failed+=("$t"); fi
done
if ((${#failed[@]})); then
  echo "建置失敗：${failed[*]}" >&2
  exit 1
fi
