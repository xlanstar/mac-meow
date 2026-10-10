#!/bin/bash
# 擷取執行中 Wine 程序的堆疊／取樣（唯讀：不啟動或結束 Wine、不修改程序記憶體）。記錄寫到 debug/。
#
# 用法：bash tools/diag/stack.sh [--exe <名稱>] [--pid <pid>]... <模式> [參數]
#   --exe <名稱>             目標程序的 exe 檔名（預設 TARGET_EXE，未設定時為遊戲主程式）
#   --pid <pid>              直接指定 macOS PID（可重複；不支援 wine 模式）
#   mach [額外 pid...]       （預設）Mach API 讀取所有執行緒的原生／x86 狀態並解析符號；程序被 task_suspend 約 1 秒。
#                            不依賴 LLDB／Rosetta 除錯協定，對「收不到訊號、LLDB 無法暫停」的程序也有效。
#   prof [次數=20] [間隔=0.5]  連續 mach 快照，統計各執行緒 CPU 增量與最常見呼叫鏈。
#   lldb                     LLDB 附加，擷取所有執行緒原生堆疊後 detach（程序短暫停住）。
#   wine                     winedbg 附加 Windows 程序，逐執行緒 bt（Windows 端堆疊，含 PE 符號）後 detach（尚未實測；確認可用後移除 tools/src/wthreads）。
# mach、prof、lldb 需要先執行 bash tools/diag/sign-debug.sh apply（get-task-allow）；wine 不需要。
# mach 的符號解析（symbolize.py）與 prof 的統計（machprof.py）用 python3；沒有 python3 時 mach 只輸出未解析的位址，prof 無法統計。
set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

SRC="$ROOT/tools/src/machstack"
export SYMX86="$TOOLS_BIN/symx86" # symbolize.py 使用

USAGE="[--exe <名稱>] [--pid <pid>]... mach|prof|lldb|wine [參數]"
pids="" # 空白分隔
while (($#)); do
  case "$1" in
    --exe)
      [[ -n "${2:-}" ]] || usage "$USAGE"
      TARGET_EXE="$2"
      shift 2
      ;;
    --pid)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || usage "$USAGE"
      pids+="$2 "
      shift 2
      ;;
    *) break ;;
  esac
done
by_pid="$pids"
[[ -n "$pids" ]] || pids="$(target_pids | tr '\n' ' ')"

require_target() { [[ -n "${pids// /}" ]] || die "沒有執行中的 ${TARGET_EXE}"; }

# symbolize <raw> <out>：替 machstack 輸出補上 x86 符號；失敗時保留原始輸出。
symbolize() {
  python3 "$SRC/symbolize.py" "$1" >"$2" 2>/dev/null || cp "$1" "$2"
}

cmd_mach() {
  need_tool machstack symx86
  local targets="$pids $*" pid out
  [[ -n "${targets// /}" ]] || die "沒有執行中的 ${TARGET_EXE}"
  out="$(out_dir machstack)"
  for pid in $targets; do
    "$TOOLS_BIN/machstack" "$pid" >"$out/raw-$pid.txt" 2>&1 || true
    symbolize "$out/raw-$pid.txt" "$out/stack-$pid.txt"
    echo "$out/stack-$pid.txt"
  done
}

cmd_prof() {
  need_tool machstack symx86
  local n="${1:-20}" gap="${2:-0.5}" pid out i
  require_target
  pid="${pids%% *}"
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

cmd_lldb() {
  local pid out
  require_target
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

# winedbg 的 `info thread`：程序行「<wpid 8 位 hex>[ (D)] <exe 檔名>」，其下執行緒行「<tab><tid> <prio> ...」。
# 只取 TARGET_EXE 的「wpid tid」（只有 exe 檔名，不含命令列參數；不分大小寫）。
target_wine_threads() {
  EXE="$TARGET_EXE" /usr/bin/awk '
    BEGIN { t = tolower(ENVIRON["EXE"]) }
    { sub(/\r$/, "") }
    /^[0-9a-f]+ / { n = tolower($NF); wpid = $1; keep = (n == t || substr(n, length(n) - length(t)) == "\\" t); next }
    keep && /^\t[0-9a-f]+ / { print wpid, $1 }
  ' "$1"
}

# 不用 `bt all`：它會逐一附加 bottle 內所有程序。改為只附加 TARGET_EXE，逐一 `bt <tid>`；結束時 winedbg 會 detach。
cmd_wine() {
  local out wpid cmds tid
  [[ -z "$by_pid" ]] || die "wine 模式以 Windows 端 exe 檔名比對，請改用 --exe"
  require_target # 確認 Wine 已在執行，避免 run_wine 啟動新的 wineserver
  out="$(out_dir winedbg)"
  run_wine winedbg --command "info thread" >"$out/threads.txt" 2>&1 || true
  target_wine_threads "$out/threads.txt" >"$out/target-threads.txt"
  [[ -s "$out/target-threads.txt" ]] || die "winedbg 找不到 ${TARGET_EXE}，見 ${out}/threads.txt"
  for wpid in $(/usr/bin/awk '{ print $1 }' "$out/target-threads.txt" | sort -u); do
    cmds=""
    for tid in $(/usr/bin/awk -v p="$wpid" '$1 == p { print $2 }' "$out/target-threads.txt"); do
      cmds+="bt 0x$tid"$'\n' # 每行一個指令（--command 的字串原樣寫入指令檔）
    done
    echo "winedbg 擷取 wpid=0x${wpid} ..."
    run_wine winedbg --command "$cmds" "0x$wpid" >"$out/bt-$wpid.txt" 2>&1 \
      || echo "winedbg 失敗，見 ${out}/bt-${wpid}.txt" >&2
  done
  echo "$out"
}

mode="${1:-mach}"
shift || true
case "$mode" in
  mach | prof | lldb | wine) "cmd_$mode" "$@" ;;
  *) usage "$USAGE" ;;
esac
