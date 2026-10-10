#!/bin/bash
# 擷取執行中 MapleStory.exe 的堆疊／取樣（唯讀：不啟動或結束 Wine、不修改程序記憶體）。紀錄寫到 debug/。
#
# 用法：bash tools/stack.sh <模式> [參數]
#   mach [額外 pid...]       （預設）Mach API 讀取所有執行緒的原生／x86 狀態並解析符號；程序被 task_suspend 約 1 秒。
#                            不依賴 LLDB／Rosetta 除錯協定，對「收不到訊號、LLDB 無法暫停」的程序也有效。
#   prof [次數=20] [間隔=0.5]  連續 mach 快照，統計各執行緒 CPU 增量與最常見呼叫鏈。
#   lldb                     LLDB 附加，擷取所有執行緒原生堆疊後 detach（程序短暫停住）。
#   wine                     winedbg 附加 Windows 程序，逐執行緒 bt（Windows 端堆疊，含 PE 符號）後 detach。
# mach、prof、lldb 需要先執行 bash tools/sign-debug.sh apply（get-task-allow）；wine 不需要。
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

SRC="$ROOT/tools/src/machstack"
export SYMX86="$TOOLS_BIN/symx86" # symbolize.py 使用

pids="$(maple_pids)"

require_maple() { [[ -n "$pids" ]] || die "沒有執行中的 MapleStory.exe"; }

# symbolize <raw> <out>：替 machstack 輸出補上 x86 符號；失敗時保留原始輸出。
symbolize() {
  python3 "$SRC/symbolize.py" "$1" >"$2" 2>/dev/null || cp "$1" "$2"
}

cmd_mach() {
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

cmd_prof() {
  need_tool machstack symx86
  local n="${1:-20}" gap="${2:-0.5}" pid out i
  require_maple
  pid="$(echo "$pids" | head -1)"
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
  require_maple
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
# 只取 MapleStory.exe 的「wpid tid」（只有 exe 檔名，不含命令列參數）。
maple_wine_threads() {
  /usr/bin/awk '
    { sub(/\r$/, "") }
    /^[0-9a-f]+ / { wpid = $1; keep = (tolower($NF) ~ /(^|\\)maplestory\.exe$/); next }
    keep && /^\t[0-9a-f]+ / { print wpid, $1 }
  ' "$1"
}

# 不用 `bt all`：它會逐一附加 bottle 內所有程序。改為只附加 MapleStory.exe，逐一 `bt <tid>`；結束時 winedbg 會 detach。
cmd_wine() {
  local out wpid cmds tid
  require_maple # 確認 Wine 已在執行，避免 run_wine 啟動新的 wineserver
  out="$(out_dir winedbg)"
  run_wine winedbg --command "info thread" >"$out/threads.txt" 2>&1 || true
  maple_wine_threads "$out/threads.txt" >"$out/maple-threads.txt"
  [[ -s "$out/maple-threads.txt" ]] || die "winedbg 找不到 MapleStory.exe，見 ${out}/threads.txt"
  for wpid in $(/usr/bin/awk '{ print $1 }' "$out/maple-threads.txt" | sort -u); do
    cmds=""
    for tid in $(/usr/bin/awk -v p="$wpid" '$1 == p { print $2 }' "$out/maple-threads.txt"); do
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
  *) usage "mach|prof|lldb|wine [參數]" ;;
esac
