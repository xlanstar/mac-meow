#!/bin/bash
# 擷取執行中 Wine 程序的堆疊／取樣（唯讀：不啟動或結束 Wine、不修改程序記憶體）。記錄寫到 debug/。
#
# 用法：bash tools/diag/stack.sh [--exe <名稱>] [--pid <pid>]... <模式> [參數]
#   --exe <名稱>             目標程序的 exe 檔名（預設 TARGET_EXE，未設定時為遊戲主程式）
#   --pid <pid>              直接指定 macOS PID（可重複；不支援 wine 模式）
#   mach [額外 pid...]       （預設）Mach API 讀取所有執行緒的原生／x86 狀態並解析符號；程序被 task_suspend 約 1 秒。
#                            不依賴 LLDB／Rosetta 除錯協定，對「收不到訊號、LLDB 無法暫停」的程序也有效。
#   prof [次數=20] [間隔=0.5]  連續 mach 快照，統計各執行緒 CPU 增量與最常見呼叫鏈。
#   hitch [秒數=60] [間隔ms=5]  卡頓（FPS drop）分析：連續取樣（machsample）同時要求 Metal HUD 產生同樣長度的
#                            效能報告（逐幀時間），以 hitchprof.py 比較掉幀期間與平常，報告寫到 report.txt。
#                            秒數只能是 HUD 支援的報告長度 5|30|60|300。不暫停程序（約佔一個核心的 10%）；
#                            擷取期間照常玩，等卡頓發生。需要遊戲開著效能 HUD（App 設定「顯示效能 HUD」，
#                            重新開遊戲後生效）。換門檻重新分析：
#                            python3 tools/src/machstack/hitchprof.py <輸出>/samples.txt <輸出>/hud-report.html \
#                              --start-us "$(cat <輸出>/report-start.txt)" --threshold-ms N
#   lldb                     LLDB 附加，擷取所有執行緒原生堆疊後 detach（程序短暫停住）。
#   wine                     winedbg 附加 Windows 程序，逐執行緒 bt（Windows 端堆疊，含 PE 符號）後 detach（尚未實測；確認可用後移除 tools/src/wthreads）。
# mach、prof、hitch、lldb 需要先執行 bash tools/diag/sign-debug.sh apply（get-task-allow）；wine 不需要。
# mach 的符號解析（symbolize.py）、prof 與 hitch 的統計（machprof.py、hitchprof.py）用 python3；沒有 python3 時
# mach 只輸出未解析的位址，prof、hitch 只留下原始取樣。
set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

SRC="$ROOT/tools/src/machstack"
export SYMX86="$TOOLS_BIN/symx86" # symbolize.py 使用

USAGE="[--exe <名稱>] [--pid <pid>]... mach|prof|hitch|lldb|wine [參數]"
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

# ---------- hitch ----------

# hud_report <秒數>：要求所有開著 Metal HUD 的程序產生效能報告（同 HUD 選單的 Generate Performance Report），
# 輸出要求的時間（epoch 微秒）。報告寫到程序的暫存資料夾：libMTLHud_<程序>_<開始時間>_<秒數>s.html
hud_report() {
  /usr/bin/perl -MTime::HiRes=time -e \
    'my $t = time; system("/usr/bin/notifyutil", "-p", $ARGV[0]) == 0 or exit 1; printf "%d\n", ($t + time) / 2 * 1e6' \
    "com.apple.metal.hud.notify.PerformanceReport-$1s"
}

# new_report <名稱前綴> <標記檔>：標記檔之後產生的最新報告
new_report() {
  find "$(getconf DARWIN_USER_TEMP_DIR)" -maxdepth 1 -name "libMTLHud_$1_*.html" -newer "$2" 2>/dev/null \
    | sort | tail -1
}

report_ready() { [[ -n "$(new_report "$@")" ]]; }

cmd_hitch() {
  local secs="${1:-60}" gap="${2:-5}" pid name out start sampler report
  [[ "$secs" =~ ^(5|30|60|300)$ && "$gap" =~ ^[0-9]+$ && "$gap" -gt 0 ]] || usage "$USAGE"
  need_tool machsample symx86
  require_target
  pid="${pids%% *}"
  # 報告檔名用程序名稱（不含 .exe）；--pid 指定的非遊戲程序就接受任何報告
  name="${TARGET_EXE%.exe}"
  [[ "$(/bin/ps -o comm= -p "$pid")" == *"$TARGET_EXE"* ]] || name="*"
  out="$(out_dir hitch)"
  touch "$out/.mark"

  echo "取樣 PID ${pid} ${secs} 秒，照常遊戲（Ctrl+C 中止）..."
  # HUD 收到要求後約 3 秒才開始收集（見 hitchprof.py 的 FALLBACK_OFFSET_MS）；取樣涵蓋到報告結束後約 1 秒
  "$TOOLS_BIN/machsample" "$pid" "$gap" "$((secs + 5))" >"$out/samples.txt" &
  sampler=$!
  sleep 0.5
  start="$(hud_report "$secs")" || die "無法送出 HUD 報告要求"
  echo "$start" >"$out/report-start.txt"
  wait "$sampler" || die "machsample 失敗（需要 sign-debug apply 後重新開遊戲）"

  # 報告在收集結束後數秒才寫出
  wait_until 20 report_ready "$name" "$out/.mark" \
    || die "等不到 Metal HUD 效能報告：請在 App 設定開啟「顯示效能 HUD」並重新開遊戲，且遊戲視窗要在畫面上"
  report="$(new_report "$name" "$out/.mark")"
  cp "$report" "$out/hud-report.html"
  rm -f "$out/.mark"
  python3 "$SRC/hitchprof.py" "$out/samples.txt" "$out/hud-report.html" --start-us "$start" | tee "$out/report.txt"
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
  mach | prof | hitch | lldb | wine) "cmd_$mode" "$@" ;;
  *) usage "$USAGE" ;;
esac
