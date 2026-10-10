#!/bin/bash
# 建置 tools/src/ 下的診斷工具，產物放在 build/tools/（不污染原始碼目錄）。
#
# 用法：bash tools/build.sh [目標...]   （不指定則建置全部；個別失敗不中斷，最後回報）
#
# macOS 工具（只需 Xcode clang）：
#   machstack                原生 arm64，以 Mach API 讀 Rosetta 程序（src/machstack）
#   symx86                   x86_64，在 Rosetta 下以 dladdr 解析 shared cache 符號
# Windows 工具（Homebrew llvm lld，見 Brewfile）：
#   wthreads.exe             不需 Windows SDK：自行宣告 API，以 llvm-dlltool 產生 import lib（lib.sh 的 nosdk_exe）
#   wgui.exe recvcheck.exe   使用 Wine 建置樹的標頭與 import lib（先執行 tools/build-wine-dlls.sh）
set -uo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

SRC="$ROOT/tools/src"
ALL=(machstack symx86 wthreads.exe wgui.exe recvcheck.exe)

# mac_tool <名稱> <來源目錄> [clang 參數...]
mac_tool() {
  local name="$1" dir="$2"
  shift 2
  /usr/bin/clang -O1 "$@" -o "$TOOLS_BIN/$name" "$SRC/$dir/$name.c"
}

# winetree_exe <名稱> "<連結參數>" <Wine dll...>：以 Wine 建置樹的標頭與 import lib 建置。
winetree_exe() {
  local name="$1" ldflags="$2"
  shift 2
  local wsrc="$ROOT/build/src/sources/wine" wobj="$ROOT/build/wine64" d libs=()
  llvm_paths || return 1
  [[ -f "$wobj/Makefile" ]] || {
    echo "缺少 Wine 建置樹（先執行 bash tools/build-wine-dlls.sh）" >&2
    return 1
  }
  for d in "$@"; do libs+=("$wobj/dlls/$d/x86_64-windows/lib$d.a"); done
  # shellcheck disable=SC2086  # ldflags 需分詞
  PATH="$LLD_BIN:$PATH" "$LLVM_BIN/clang" --target=x86_64-windows -fuse-ld=lld -nostdlib -nostdinc \
    -I"$wobj/include" -I"$wsrc/include" -I"$wsrc/include/msvcrt" -D__WINESRC__ -O1 \
    -o "$TOOLS_BIN/$name.exe" "$SRC/$name/$name.c" $ldflags "${libs[@]}"
}

build_one() {
  case "$1" in
    machstack) mac_tool machstack machstack -g -Wall ;;
    symx86) mac_tool symx86 machstack -arch x86_64 ;;
    wthreads.exe)
      nosdk_exe "$SRC/wthreads/wthreads.c" "$TOOLS_BIN/wthreads.exe" "$NOSDK_MSVCRT" "ntdll:NtQueryInformationThread" \
        "kernel32:CreateToolhelp32Snapshot Thread32First Thread32Next Module32FirstW Module32NextW OpenThread OpenProcess SuspendThread ResumeThread GetThreadContext ReadProcessMemory CloseHandle GetLastError"
      ;;
    wgui.exe) winetree_exe wgui "-Wl,-entry:start -Wl,-subsystem:console" shell32 ucrtbase user32 gdi32 kernel32 ;;
    recvcheck.exe) winetree_exe recvcheck "-Wl,-entry:main" ws2_32 kernel32 ucrtbase ;;
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
