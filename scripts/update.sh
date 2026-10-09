#!/bin/bash
# MacMeow.app 一鍵更新（由 App 的「更新」呼叫；只用 macOS 內建指令）。
#   update.sh prepare <X.Y.Z> <目前的 .app>
#     App 仍在執行時：只用 https 從 $MACMEOW_REPO 的 Release vX.Y.Z 下載 MacMeow-X.Y.Z.dmg 與 .sha256 並比對雜湊
#     （同一來源，只確認完整），取出新版 App，驗證簽章符合 MACMEOW_REQUIREMENT（官方 Team ID，與目前 App
#     是否為自行建置的 ad-hoc 版無關）與版本，暫存到 $MACMEOW_CACHE/update。
#     dmg 可續傳：斷線或停滯時等待後從中斷處繼續，下次執行 prepare 也會接著下載（見 download）。
#     輸出「@@PROGRESS <0-100>」（下載進度）與「@@WAIT」（等待網路）；失敗時不影響目前版本，
#     最後一行錯誤訊息由 App 顯示。
#   update.sh install <目前的 .app> <App PID>
#     App 啟動後隨即結束；本指令等 App 結束後以暫存的新版取代並重新開啟。
#     取代失敗時還原舊版並重新開啟。輸出寫到 $MACMEOW_LOGS/update.log。
#   update.sh homebrew <目前的 .app>
#     App 由 Homebrew cask 安裝時輸出更新指令（brew upgrade --cask …）並回傳 0，否則回傳 1。
#     Homebrew 安裝的 App 不做一鍵更新，交給 brew 升級，Homebrew 記錄的版本才會一致。
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

UPDATE_DIR="$MACMEOW_CACHE/update"

usage() { die "用法：update.sh prepare <X.Y.Z> <目前的 .app> | install <目前的 .app> <App PID> | homebrew <目前的 .app>"; }

plist_value() { /usr/libexec/PlistBuddy -c "Print $2" "$1/Contents/Info.plist" 2>/dev/null; }
# shellcheck disable=SC2329  # 由 wait_until 呼叫
pid_gone() { ! kill -0 "$1" 2>/dev/null; }

# 下載重試：連續 RETRY_LIMIT 次沒有任何進展（每次間隔 RETRY_DELAY 秒）才放棄，約 5–10 分鐘。
RETRY_LIMIT=30
RETRY_DELAY=10

file_size() { /usr/bin/stat -f %z "$1" 2>/dev/null || echo 0; }

# curl_progress <網址> <檔案>：從檔案現有大小續傳（-C -；已完整時 curl 直接成功）；
# 30 秒內平均低於 1 KB/s 視為斷線（網路中斷時 TCP 連線可能一直不回應）。
# curl 的進度列以 \r 更新同一行，轉成每行一個「@@PROGRESS <百分比>」（續傳時含已下載部分）；
# 跳過轉址回應開頭的 100%。最後的 HTTP 狀態碼寫到 <檔案>.http（連不上時為 000）。
curl_progress() {
  /usr/bin/curl -fL --proto '=https' --proto-redir '=https' -# -C - --connect-timeout 15 --speed-limit 1024 --speed-time 30 -w '%{http_code}' \
    -o "$2" "$1" 2>&1 >"$2.http" \
    | /usr/bin/awk 'BEGIN { RS = "\r" }
      match($0, /[0-9]+(\.[0-9]+)?%/) {
        p = int(substr($0, RSTART, RLENGTH - 1))
        if (!started && p == 100) next
        started = 1
        if (p != last) { print "@@PROGRESS " p; last = p; fflush() }
      }'
  return "${PIPESTATUS[0]}"
}

# download <網址> <檔案>：可續傳下載；連線失敗或中斷時輸出 @@WAIT，等待後從中斷處繼續。
# 有進展就重新計算重試次數；伺服器明確拒絕（4xx，逾時與限流除外）或轉址到非 https 時不重試。
# curl 8 經 HTTP/2 時 -f 的錯誤碼是 56 而非 22，所以改看 HTTP 狀態碼。
download() {
  local url="$1" out="$2" fails=0 before rc http
  while :; do
    before="$(file_size "$out")"
    rc=0
    curl_progress "$url" "$out" || rc=$?
    http="$(cat "$out.http" 2>/dev/null)" || http=000
    rm -f "$out.http"
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;; # 不支援的協定：轉址到非 https 時（--proto-redir），不重試
    esac
    case "$http" in
      408 | 429) ;;
      4??) return 1 ;;
    esac
    if (($(file_size "$out") > before)); then fails=0; else fails=$((fails + 1)); fi
    ((fails < RETRY_LIMIT)) || return 1
    echo "@@WAIT"
    echo "下載中斷（curl ${rc}，HTTP ${http}），${RETRY_DELAY} 秒後繼續"
    sleep "$RETRY_DELAY"
  done
}

# dmg_matches <dmg>：與同名 .sha256 相符
dmg_matches() { [[ "$(sha256 "$1")" == "$(/usr/bin/cut -d' ' -f1 "$1.sha256")" ]]; }

# check_target <.app>：目前的 App 可以被原地取代
check_target() {
  [[ "$1" == *.app && -f "$1/Contents/Info.plist" ]] || die "找不到目前的 App：${1}"
  [[ "$1" != */AppTranslocation/* ]] || die "請先把 MacMeow.app 移到「應用程式」資料夾再更新"
  [[ -w "$1" && -w "$(dirname "$1")" ]] || die "沒有權限取代 ${1}"
}

# homebrew_command <.app>：App 由 Homebrew cask 安裝時輸出更新指令（判斷見 common.sh 的 homebrew_app）。
homebrew_command() {
  homebrew_app "$1" || return 1
  echo "brew upgrade --cask $MACMEOW_CASK"
}

# verify_app <新版 .app> <X.Y.Z>：官方簽章（MACMEOW_REQUIREMENT，含 bundle id）且版本正確
verify_app() {
  /usr/bin/codesign --verify --deep --strict -R="$MACMEOW_REQUIREMENT" "$1" 2>/dev/null \
    || die "新版不是官方簽章的 MacMeow.app"
  [[ "$(plist_value "$1" CFBundleShortVersionString)" == "$2" ]] || die "下載的版本不是 ${2}"
}

cmd_prepare() {
  (($# == 2)) || usage
  local v="$1" target="$2" url dmg mnt copied=0 brew_cmd
  [[ "$v" =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "版本號不正確：${v}"
  # 網址由版本號組成，不接受外部傳入（只會下載本專案的 Release 附件，命名同 tools/release.sh）
  url="https://github.com/$MACMEOW_REPO/releases/download/v$v/MacMeow-$v.dmg"
  if brew_cmd="$(homebrew_command "$target")"; then
    die "這個 App 由 Homebrew 安裝，請在終端機執行：${brew_cmd}"
  fi
  check_target "$target"
  # 保留同一個 dmg 的未完成下載以便續傳，其餘（舊版 dmg、上次取出的 App）刪除
  dmg="$UPDATE_DIR/${url##*/}"
  mkdir -p "$UPDATE_DIR"
  /usr/bin/find "$UPDATE_DIR" -mindepth 1 -maxdepth 1 ! -name "${dmg##*/}" -exec rm -rf {} +
  echo "下載 ${url##*/}"
  if ! download "$url" "$dmg" || ! download "$url.sha256" "$dmg.sha256"; then
    die "下載失敗，請檢查網路連線"
  fi
  # 雜湊不符（例如續傳的舊檔已損壞）時刪除並重新下載一次
  if ! dmg_matches "$dmg"; then
    rm -f "$dmg"
    download "$url" "$dmg" || die "下載失敗，請檢查網路連線"
    dmg_matches "$dmg" || {
      rm -f "$dmg"
      die "下載的檔案不完整，請再試一次"
    }
  fi

  mnt="$UPDATE_DIR/mnt"
  dmg_attach --nobrowse --readonly --mountpoint "$mnt" "$dmg" >/dev/null || die "無法開啟下載的 dmg"
  /usr/bin/ditto "$mnt/MacMeow.app" "$UPDATE_DIR/MacMeow.app" && copied=1
  /usr/bin/hdiutil detach -quiet -force "$mnt" || true
  ((copied)) || die "無法從 dmg 取出 MacMeow.app"

  verify_app "$UPDATE_DIR/MacMeow.app" "$v"
  echo "已下載並驗證 ${v}"
}

cmd_install() {
  (($# == 2)) || usage
  local target="$1" pid="$2" new old ok=0
  mkdir -p "$MACMEOW_LOGS"
  exec >>"$MACMEOW_LOGS/update.log" 2>&1 </dev/null
  echo "===== $(date '+%F %T') 更新 ====="
  wait_until 60 pid_gone "$pid" || die "App 沒有結束，取消更新"

  # 先複製到同一個資料夾再改名，取代只需兩次 rename；任何一步失敗都保留或還原舊版
  new="$(dirname "$target")/.$(basename "$target").macmeow-new"
  old="${new%-new}-old"
  rm -rf "$new" "$old"
  if [[ -d "$UPDATE_DIR/MacMeow.app" ]] && /usr/bin/ditto "$UPDATE_DIR/MacMeow.app" "$new" \
    && mv "$target" "$old"; then
    if mv "$new" "$target"; then
      ok=1
    else
      mv "$old" "$target" || die "還原失敗，舊版在 ${old}"
    fi
  fi
  rm -rf "$new" "$old" "$UPDATE_DIR"
  if ((ok)); then
    echo "已更新為 $(plist_value "$target" CFBundleShortVersionString)"
  else
    echo "取代 App 失敗，保留原本的版本" >&2
  fi
  /usr/bin/open "$target"
  ((ok))
}

# 整段先讀完再執行：install 會取代這個腳本所在的 App。
{
  case "${1:-}" in
    prepare) shift && cmd_prepare "$@" ;;
    install) shift && cmd_install "$@" ;;
    homebrew)
      shift
      (($# == 1)) || usage
      homebrew_command "$1"
      ;;
    *) usage ;;
  esac
  exit
}
