#!/bin/bash
# 擷取執行中 MapleStory.exe 的堆疊／取樣（唯讀：不啟動或結束 Wine、不修改程序記憶體）。紀錄寫到 debug/。
#
# 用法：bash tools/stack.sh <模式> [參數]
#   mach [額外 pid...]       （預設）Mach API 讀取所有執行緒的原生／x86 狀態並解析符號；程序被 task_suspend 約 1 秒。
#                            不依賴 LLDB／Rosetta 除錯協定，對「收不到訊號、LLDB 無法暫停」的程序也有效。
#   prof [次數=20] [間隔=0.5]  連續 mach 快照，統計各執行緒 CPU 增量與最常見呼叫鏈。
#   lldb                     LLDB 附加，擷取所有執行緒原生堆疊後 detach（程序短暫停住）。
#   sample                   macOS sample 3 秒（Rosetta 下常在 CoreSymbolication 內崩潰，見 docs/development.md）。
# mach、prof、lldb 需要先執行 bash tools/sign-debug.sh apply（get-task-allow）。
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

SRC="$ROOT/tools/src/machstack"
export SYMX86="$TOOLS_BIN/symx86"   # symbolize.py 使用

pids="$(maple_pids)"

# symbolize <raw> <out>：替 machstack 輸出補上 x86 符號；失敗時保留原始輸出。
symbolize() {
  python3 "$SRC/symbolize.py" "$1" >"$2" 2>/dev/null || cp "$1" "$2"
}

mode_mach() {
  need_tool machstack symx86
  local targets="$pids $*" pid out
  [[ -n "${targets// /}" ]] || die "沒有執行中的 MapleStory.exe"
  out="$(out_dir machstack)"
  for pid in $targets; do
    "$TOOLS_BIN/machstack" "$pid" >"$out/raw-$pid.txt" 2>&1 || true
    symbolize "$out/raw-$pid.txt" "$out/stack-$pid.txt"
    echo "$out/stack-$pid.txt"
  done
}

mode_prof() {
  need_tool machstack symx86
  local n="${1:-20}" gap="${2:-0.5}" pid out i
  pid="$(echo "$pids" | head -1)"
  [[ -n "$pid" ]] || die "沒有執行中的 MapleStory.exe"
  out="$(out_dir machprof)"
  for i in $(seq -w 1 "$n"); do
    "$TOOLS_BIN/machstack" "$pid" >"$out/raw-$i.txt" 2>&1 || true
    sleep "$gap"
  done
  cat "$out"/raw-*.txt >"$out/all.txt"
  symbolize "$out/all.txt" "$out/sym.txt"
  python3 "$SRC/machprof.py" "$out/sym.txt" | tee "$out/summary.txt"
  echo "$out"
}

mode_lldb() {
  local pid out
  [[ -n "$pids" ]] || die "沒有執行中的 MapleStory.exe"
  out="$(out_dir lldb)"
  for pid in $pids; do
    echo "LLDB 擷取 PID=${pid} ..."
    xcrun lldb --batch -p "$pid" \
      -o 'thread list' \
      -o 'thread backtrace all -c 40' \
      -o 'process detach' >"$out/bt-$pid.txt" 2>&1 || echo "lldb 失敗，見 ${out}/bt-${pid}.txt" >&2
  done
  echo "$out"
}

mode_sample() {
  local pid out rc status=0
  [[ -n "$pids" ]] || die "沒有執行中的 MapleStory.exe"
  out="$(out_dir sample)"
  for pid in $pids; do
    echo "取樣 MapleStory.exe PID=${pid}（3 秒，不會結束程序）"
    rc=0
    /usr/bin/sample "$pid" 3 10 -file "$out/sample-$pid.txt" >"$out/sample-$pid-status.txt" 2>&1 || rc=$?
    (( rc == 0 )) && continue
    status=1
    if (( rc > 128 )); then
      echo "sample 被 signal $((rc - 128)) 結束（工具本身失敗，不代表遊戲崩潰；見 ~/Library/Logs/DiagnosticReports/sample-*.ips）。改用 tools/stack.sh mach。" >&2
    else
      echo "sample 失敗（exit ${rc}，程序可能已退出），詳見 ${out}/sample-${pid}-status.txt" >&2
    fi
  done
  echo "$out"
  return $status
}

mode="${1:-mach}"; shift || true
case "$mode" in
  mach | prof | lldb | sample) "mode_$mode" "$@" ;;
  *) echo "用法：$0 mach|prof|lldb|sample [參數]" >&2; exit 64 ;;
esac
