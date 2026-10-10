#!/bin/bash
# 建置實驗程式到 build/experiments/<實驗>/。
#
# 用法：bash experiments/build.sh [實驗...]   （不指定則建置全部；個別失敗不中斷，最後回報）
set -uo pipefail
# shellcheck source=../tools/lib.sh
source "$(cd "$(dirname "$0")/.." && pwd)/tools/lib.sh"

ALL=(smc-same-page rsaenh-reload rosetta-probes)

# mac_bins <輸出目錄> <來源目錄> <clang 參數> <名稱...>
mac_bins() {
  local out="$1" src="$2" flags="$3" n
  shift 3
  for n in "$@"; do
    # shellcheck disable=SC2086  # flags 需分詞
    /usr/bin/clang -O1 $flags -o "$out/$n" "$src/$n.c" || return 1
  done
}

build_one() {
  local src="$ROOT/experiments/$1" out="$ROOT/build/experiments/$1"
  mkdir -p "$out"
  case "$1" in
    smc-same-page) mac_bins "$out" "$src" "-arch x86_64" smctest smctest2 smctest3 ;;
    rosetta-probes) mac_bins "$out" "$src" "-g -Wall" callchain memdump ;;
    rsaenh-reload)
      nosdk_exe "$src/reloadtest.c" "$out/reloadtest.exe" "$NOSDK_MSVCRT" \
        "kernel32:LoadLibraryA FreeLibrary GetProcAddress CreateThread GetTickCount"
      ;;
    *)
      echo "未知實驗：$1（可用：${ALL[*]}）" >&2
      return 1
      ;;
  esac
}

(($#)) || set -- "${ALL[@]}"
failed=()
for e in "$@"; do
  if build_one "$e"; then echo "完成：build/experiments/$e"; else failed+=("$e"); fi
done
if ((${#failed[@]})); then
  echo "建置失敗：${failed[*]}" >&2
  exit 1
fi
