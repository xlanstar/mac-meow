#!/bin/bash
# 遊戲結束時自動收尾（docs/architecture.md「遊戲階段監看」）。
# 監看本專案啟動的 Windows 程式（session_procs）：遊戲關閉，或登入器關閉且遊戲沒在執行，就結束登入器、
# 認證器、HostShield 等本專案的程式。其他 Wine 程式都不碰，最後一個使用者程式結束後 Wine 會自己關閉。
#
# 用法：bash scripts/session.sh start|watch|close|status|cleanup
#   start    在背景啟動 watch（已在執行就不重複啟動），由 play.sh 呼叫
#   watch    監看直到收尾或 Wine 結束（前景執行；同時只會有一個）
#   close    立即收尾（先停止執行中的 watch，避免它沿用這次之前的狀態）
#   status   watch 在執行則回傳 0
#   cleanup  結束 Cyder 遺留的 sentinel 程序（其啟動流程已結束、但程序沒有退出）
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

PID_FILE="$MACMEOW_SUPPORT/session-watch.pid"
LOG_FILE="$MACMEOW_LOGS/session.log"
POLL=2          # 檢查間隔（秒）
END_CHECKS=3    # 連續幾次判定結束才收尾（避免遊戲重啟、登入器切換時的空檔）
NO_LAUNCHER=300 # 啟動後幾秒內一直沒看到登入器，視為啟動失敗並收尾

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

watcher_pid() {
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  /bin/ps -p "$pid" -o args= 2>/dev/null | /usr/bin/grep -q 'session\.sh watch' || return 1
  echo "$pid"
}

session_pids() { session_procs | /usr/bin/awk '{print $1}'; }
no_session_procs() { [[ -z "$(session_procs)" ]]; }
wine_stopped_or_foreign() { wine_stopped || [[ -n "$(foreign_wine_procs)" ]]; }

# 停止執行中的 watch（不是自己時）並等它退出，最多 10 秒。
stop_watcher() {
  local pid
  pid="$(watcher_pid)" || return 0
  [[ "$pid" != "$$" ]] || return 0
  kill "$pid" 2>/dev/null || return 0
  wait_until 10 watcher_gone || log "監看程序（PID ${pid}）沒有結束"
}
watcher_gone() { ! watcher_pid >/dev/null; }

# 已結束的 Cyder sentinel（Cyder 0.13 每次啟動遺留一組 CyderSwift --sentinel-connect 與其 bash）：
# Cyder 在 Wine 結束後才刪除 --fifo 所在的暫存資料夾；資料夾已不存在，或監督它的 bash 已結束
# （PPID 為 1），這個 sentinel 就不會再被使用，卻不會自行退出。只在 Wine 沒有執行時呼叫。
cleanup_sentinels() {
  local pid ppid fifo n=0
  while read -r pid ppid fifo; do
    [[ -n "$fifo" ]] || continue
    [[ ! -e "$fifo" || "$ppid" == 1 ]] || continue
    kill "$pid" 2>/dev/null && n=$((n + 1))
  done < <(/bin/ps -axo pid=,ppid=,args= \
    | /usr/bin/sed -n 's|^ *\([0-9]*\) *\([0-9]*\) .*/Cyder\.app/Contents/MacOS/CyderSwift --sentinel-connect .* --fifo \([^ ]*\).*|\1 \2 \3|p')
  ((n == 0)) || log "已結束 ${n} 個 Cyder 遺留的 sentinel 程序"
}

close_session() {
  local pids
  pids="$(session_pids)"
  if [[ -n "$pids" ]]; then
    log "關閉：$(session_procs | /usr/bin/awk '{print $2}' | /usr/bin/sort | /usr/bin/uniq -c | /usr/bin/awk '{printf "%s×%s ", $2, $1}')"
    # shellcheck disable=SC2086  # PID 清單
    kill $pids 2>/dev/null || true
    if ! wait_until 10 no_session_procs; then
      pids="$(session_pids)"
      log "強制結束：${pids//$'\n'/ }"
      # shellcheck disable=SC2086
      [[ -z "$pids" ]] || kill -KILL $pids 2>/dev/null || true
    fi
  fi
  # 只剩 Wine 系統程式時，wineserver 會在數秒內自行結束；有其他 Windows 程式（例如其他 Cyder 遊戲）
  # 就不必等，保留 Wine。
  if wait_until 20 wine_stopped_or_foreign; then
    if wine_stopped; then log "Wine 已結束"; else log "其他 Windows 程式仍在執行，保留 Wine"; fi
  elif [[ -z "$(foreign_wine_procs)" ]]; then
    log "Wine 沒有自行結束，且沒有其他 Windows 程式在執行，關閉 wineserver"
    wineserver_kill
  else
    log "其他 Windows 程式仍在執行，保留 Wine"
  fi
  wine_running || cleanup_sentinels
}

# 本專案程式的數量：登入器、遊戲、其他（Patcher 等，執行中就不收尾）；HostShield、認證器、
# BlackCipher、NxOverlay 是隨登入器或遊戲啟動的附屬程式，不計入。
count_procs() {
  session_procs | LAUNCHER="$LAUNCHER_EXE" /usr/bin/awk '
    $2 == ENVIRON["LAUNCHER"] { l++; next }
    $2 == "MapleStory.exe" { g++; next }
    $2 !~ /^(HostShield\.exe|認證器\.exe|BlackCipher(64)?\.aes|BlackXchg\.aes|DwarfAxe\.exe)$/ { o++ }
    END { print l + 0, g + 0, o + 0 }'
}

cmd_watch() {
  local pid server launcher game other launcher_seen=0 game_seen=0 ended=0 started=$SECONDS reason
  mkdir -p "$MACMEOW_SUPPORT"
  if pid="$(watcher_pid)"; then
    log "已有監看程序（PID ${pid}）"
    return 0
  fi
  echo $$ >"$PID_FILE"
  trap '[[ "$(cat "$PID_FILE" 2>/dev/null)" == $$ ]] && rm -f "$PID_FILE"' EXIT
  server="$(wineserver_pid)"
  log "開始監看（${GAME_DIR}）"
  # Wine 結束（例如「全部關閉」）就停止；之後重新啟動的是新的 wineserver，由新的監看程序負責。
  while [[ -n "$server" && "$(wineserver_pid)" == "$server" ]]; do
    read -r launcher game other < <(count_procs)
    if ((launcher && ! launcher_seen)); then
      launcher_seen=1
      log "登入器已啟動"
    fi
    if ((game && ! game_seen)); then
      game_seen=1
      log "遊戲已啟動"
    fi
    reason=""
    if ((! game && ! other)); then
      if ((game_seen)); then
        reason="遊戲已關閉"
      elif ((launcher_seen && ! launcher)); then
        reason="登入器已關閉"
      elif ((! launcher_seen && SECONDS - started > NO_LAUNCHER)); then
        reason="${NO_LAUNCHER} 秒內沒有看到登入器"
      fi
    fi
    if [[ -z "$reason" ]]; then
      ended=0
    elif ((++ended >= END_CHECKS)); then
      log "$reason"
      close_session
      return 0
    fi
    sleep "$POLL"
  done
  log "Wine 已結束，停止監看"
  wine_running || cleanup_sentinels
}

cmd_start() {
  local pid
  if pid="$(watcher_pid)"; then
    echo "遊戲階段監看已在執行（PID ${pid}）"
    return 0
  fi
  mkdir -p "$MACMEOW_LOGS"
  # 與呼叫者（MacMeow.app／終端機）脫離：輸出寫入記錄檔，關閉 App 或終端機後仍繼續監看。
  nohup /bin/bash "$MACMEOW_SCRIPTS/session.sh" watch </dev/null >>"$LOG_FILE" 2>&1 &
  echo "已啟動遊戲階段監看：遊戲關閉後會自動關閉登入器與背景程式（記錄：${LOG_FILE}）"
}

cmd_close() {
  stop_watcher
  close_session
}

cmd_status() {
  local pid
  if pid="$(watcher_pid)"; then
    echo "遊戲階段監看：執行中（PID ${pid}）"
  else
    echo "遊戲階段監看：未執行"
    return 1
  fi
}

cmd_cleanup() { wine_running || cleanup_sentinels; }

case "${1:-}" in
  start | watch | close | status | cleanup) "cmd_$1" ;;
  *) usage "start|watch|close|status|cleanup" ;;
esac
