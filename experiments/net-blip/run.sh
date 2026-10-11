#!/bin/bash
# 同時執行原生 blip 與 Wine 內的 blip.exe，期間把 Wi-Fi 關閉數秒再打開（會中斷這台 Mac 所有網路連線）。
# 輸出：debug/net-blip/<時間>/{native,wine}.log（wine.log 含 WINEDEBUG=warn+winsock 的 sendmsg 錯誤）。
#
# 用法：bash experiments/net-blip/run.sh [關閉前秒數] [關閉秒數] [總秒數]   預設 8 5 45
set -euo pipefail
# shellcheck source=../../tools/lib.sh
source "$(cd "$(dirname "$0")/../.." && pwd)/tools/lib.sh"

BEFORE="${1:-8}" OFF="${2:-5}" TOTAL="${3:-45}"
BIN="$ROOT/build/experiments/net-blip"
OUT="$DEBUG_DIR/net-blip/$(date +%Y%m%d-%H%M%S)"
IF="$(/usr/sbin/networksetup -listallhardwareports | /usr/bin/awk '/Wi-Fi/{getline; print $2; exit}')"
[[ -n "$IF" ]] || die "找不到 Wi-Fi 介面"
[[ -x "$BIN/blip" && -f "$BIN/blip.exe" ]] || die "先執行 just exp net-blip"
mkdir -p "$OUT"
hostshields() { session_procs | /usr/bin/awk '$2 == "HostShield.exe" {printf "%s ", $1}'; }
echo "HostShield（前）：$(hostshields)" | tee "$OUT/hostshield.log"

"$BIN/blip" www.cloudflare.com "$TOTAL" >"$OUT/native.log" 2>&1 &
native=$!
(WINEDEBUG=warn+winsock run_wine "$BIN/blip.exe" www.cloudflare.com "$TOTAL" >"$OUT/wine.log" 2>&1) &
wine=$!
sleep "$BEFORE"
echo "$(date +%T) Wi-Fi off（${IF}）"
/usr/sbin/networksetup -setairportpower "$IF" off
sleep "$OFF"
echo "$(date +%T) Wi-Fi on"
/usr/sbin/networksetup -setairportpower "$IF" on
wait "$native" "$wine" || true
echo "HostShield（後）：$(hostshields)" | tee -a "$OUT/hostshield.log"
echo "輸出：$OUT"
