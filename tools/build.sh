#!/bin/bash
# 建置 tools/src/ 下的診斷工具，產物放在 build/tools/（不污染原始碼目錄）。
#
# 用法：bash tools/build.sh [目標...]   （不指定則建置全部；個別失敗不中斷，最後回報）
#
# macOS 工具（只需 Xcode clang）：
#   machstack callchain memdump   原生 arm64，以 Mach API 讀 Rosetta 程序（src/machstack）
#   symx86                        x86_64，在 Rosetta 下以 dladdr 解析 shared cache 符號
#   smctest smctest2 smctest3     x86_64，Rosetta SMC（同頁寫入）成本重現
# Windows 工具（brew install llvm lld）：
#   wthreads.exe reloadtest.exe   不需 Windows SDK：自行宣告 API，以 llvm-dlltool 產生 import lib
#   wgui.exe recvcheck.exe        使用 Wine 建置樹的標頭與 import lib（先執行 tools/build-wine-dlls.sh）
set -uo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

SRC="$ROOT/tools/src"
OUT="$TOOLS_BIN"
OBJ="$OUT/obj"
ALL=(machstack callchain memdump symx86 smctest smctest2 smctest3 wthreads.exe reloadtest.exe wgui.exe recvcheck.exe)
MSVCRT="msvcrt:printf puts strtoul _flushall __getmainargs exit"

mac_tool() { # mac_tool <名稱> <來源目錄> [clang 參數...]
  local name="$1" dir="$2"
  shift 2
  /usr/bin/clang -O1 "$@" -o "$OUT/$name" "$SRC/$dir/$name.c"
}

# nosdk_exe <名稱> <dll:匯出 匯出...>...：clang-cl 編譯 src/<名稱>/<名稱>.c + wincrt/crt0.c，
# 依清單產生 import lib，lld-link 連結（不連預設函式庫）。
nosdk_exe() {
  local name="$1"
  shift
  local o="$OBJ/$name" spec dll sym libs=()
  llvm_paths || return 1
  mkdir -p "$o"
  for spec in "$@"; do
    dll="${spec%%:*}"
    {
      echo "LIBRARY $dll.dll"
      echo EXPORTS
      for sym in ${spec#*:}; do echo "$sym"; done
    } >"$o/$dll.def"
    "$LLVM_BIN/llvm-dlltool" -m i386:x86-64 -d "$o/$dll.def" -l "$o/$dll.lib" || return 1
    libs+=("$o/$dll.lib")
  done
  "$LLVM_BIN/clang-cl" --target=x86_64-pc-windows-msvc /O1 /GS- /c "/Fo$o/" -- "$SRC/$name/$name.c" "$SRC/wincrt/crt0.c" || return 1
  "$LLD_BIN/lld-link" /subsystem:console /entry:mainCRTStartup /nodefaultlib "/out:$OUT/$name.exe" \
    "$o/$name.obj" "$o/crt0.obj" "${libs[@]}"
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
    -o "$OUT/$name.exe" "$SRC/$name/$name.c" $ldflags "${libs[@]}"
}

build_one() {
  case "$1" in
    machstack | callchain | memdump) mac_tool "$1" machstack -g -Wall ;;
    symx86) mac_tool symx86 machstack -arch x86_64 ;;
    smctest | smctest2 | smctest3) mac_tool "$1" smctest -arch x86_64 ;;
    wthreads.exe)
      nosdk_exe wthreads "$MSVCRT" "ntdll:NtQueryInformationThread" \
        "kernel32:CreateToolhelp32Snapshot Thread32First Thread32Next Module32FirstW Module32NextW OpenThread OpenProcess SuspendThread ResumeThread GetThreadContext ReadProcessMemory CloseHandle GetLastError"
      ;;
    reloadtest.exe)
      nosdk_exe reloadtest "$MSVCRT" "ntdll:RtlGetVersion" \
        "kernel32:LoadLibraryA FreeLibrary GetProcAddress CreateThread GetTickCount"
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
mkdir -p "$OUT"
failed=()
for t in "$@"; do
  if build_one "$t"; then echo "完成：build/tools/$t"; else failed+=("$t"); fi
done
if ((${#failed[@]})); then
  echo "建置失敗：${failed[*]}" >&2
  exit 1
fi
