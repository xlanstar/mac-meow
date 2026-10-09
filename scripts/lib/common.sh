# shellcheck shell=bash disable=SC2034  # 常數由 source 本檔的腳本使用
# 使用者腳本共用的路徑、常數與函式。由 scripts/*.sh、tools/lib.sh source（MacMeow.app 經由 scripts/play.sh 使用）。
# 只能用 macOS 內建指令（會打包進 MacMeow.app）；也會以 root 執行（setup-loopback.sh），不可依賴使用者環境。
[[ -n "${MACMEOW_COMMON_LOADED:-}" ]] && return 0
MACMEOW_COMMON_LOADED=1

# 以管理員權限執行時 HOME 可能未設定；bash 的 ~ 在 HOME 未設定時改查 passwd。
: "${HOME:=$(cd ~ && pwd)}"

# ---------- 路徑（可用環境變數覆寫） ----------
GAME_DIR="${GAME_DIR:-$HOME/Games/MapleStory}"
CYDER_ENGINE="${CYDER_ENGINE:-$HOME/.cyder/runtime/Engines/wine-x86_64}"
CYDER_ENGINE="${CYDER_ENGINE%/}" # wine_running 以最後一段目錄名比對，不能有結尾斜線
CYDER_SUPPORT="$HOME/Library/Application Support/Cyder"
CYDER_SETTINGS="$CYDER_SUPPORT/settings.json"
CYDER_PREFIX="$CYDER_SUPPORT/bottles/shared"
WINE_BIN="$CYDER_ENGINE/bin/wine"
WINESERVER_BIN="$CYDER_ENGINE/bin/wineserver"
# MacMeow 自己的設定與記錄（uninstall.sh 整個刪除；App 端路徑見 app/Sources/Paths.swift）。
MACMEOW_SUPPORT="$HOME/Library/Application Support/MacMeow"
MACMEOW_LOGS="$HOME/Library/Logs/MacMeow"

# ---------- 貓貓谷 ----------
GAME_FILES=(認證器.exe HostShield.exe 貓貓TMS登入器.exe XCGUI.dll MapleStory.exe)
# HostShield 各 token 的通道位址（app.ip），各監聽 HOSTSHIELD_PORTS。
HOSTSHIELD_IPS=(127.145.37.1 127.152.149.1 127.143.13.1 127.162.167.1)
HOSTSHIELD_PORTS="37601-37630"
# 登入器在 Windows 上以 netsh 掛到 Loopback 的官方 IP（docs/technical-notes.md #3）。
GAME_ALIAS_IP="202.80.104.28"
LOOPBACK_IPS=("${HOSTSHIELD_IPS[@]}" "$GAME_ALIAS_IP")
# 登入器的 exe 名稱（Dock 圖示設定以此為 Wine AppDefaults 的 key）。
LAUNCHER_EXE="貓貓TMS登入器.exe"

# ---------- 共用函式 ----------
die() {
  echo "$*" >&2
  exit 1
}

# 依序尋找 Cyder.app；找到則輸出路徑。
find_cyder() {
  local c
  for c in /Applications/Cyder.app "$HOME/Applications/Cyder.app" "$HOME/Downloads/Cyder.app"; do
    [[ -d "$c" ]] && {
      echo "$c"
      return 0
    }
  done
  return 1
}

# game_dir_valid <dir>：資料夾內有完整的遊戲與登入器檔案。
game_dir_valid() {
  local f
  for f in "${GAME_FILES[@]}"; do [[ -f "$1/$f" ]] || return 1; done
}

# missing_game_file <dir>：輸出第一個缺少的檔名。
missing_game_file() {
  local f
  for f in "${GAME_FILES[@]}"; do [[ -f "$1/$f" ]] || {
    echo "$f"
    return 0
  }; done
  return 1
}

# cyder_setting <key>：讀取 Cyder settings.json 的值（不存在則輸出空字串）。
cyder_setting() {
  /usr/bin/plutil -extract "$1" raw -o - "$CYDER_SETTINGS" 2>/dev/null || true
}

# Cyder 已建立 Windows 環境（shared bottle）且 engine 已下載。
cyder_ready() { [[ -f "$CYDER_PREFIX/system.reg" && -x "$WINE_BIN" ]]; }

# 認證器.exe（VB6）需要的 runtime 已安裝。
vb6_installed() { [[ -f "$CYDER_PREFIX/drive_c/windows/syswow64/msvbvm60.dll" ]]; }

# progress <id> <訊息>：顯示步驟訊息。MACMEOW_PROGRESS=1（MacMeow.app）時改輸出「@@STEP <id> <訊息>」供 App 解析。
progress() {
  local id="$1"
  shift
  if [[ -n "${MACMEOW_PROGRESS:-}" ]]; then echo "@@STEP $id $*"; else echo "$*"; fi
}

# Cyder engine 的 wineserver 是否在執行（= 有任何 Cyder 遊戲開著）。
wine_running() {
  /usr/bin/pgrep -f "/${CYDER_ENGINE##*/}/.*bin/wineserver" >/dev/null 2>&1
}
wine_stopped() { ! wine_running; }
# 執行中的 wineserver PID（沒有則輸出空字串）。
wineserver_pid() {
  /usr/bin/pgrep -f "/${CYDER_ENGINE##*/}/.*bin/wineserver" 2>/dev/null | /usr/bin/head -1 || true
}

# require_wine_stopped <動作說明>：Wine 執行中就拒絕修改 engine。
require_wine_stopped() {
  wine_running && die "請先關閉所有 Cyder 遊戲（包含貓貓谷）再${1}。"
  return 0
}

# 匯出 Wine client 需要的環境。client 必須與執行中的 wineserver 使用相同同步機制（依 Cyder 設定）。
export_wine_env() {
  export WINEPREFIX="$CYDER_PREFIX"
  unset WINEMSYNC WINEESYNC
  if [[ "$(cyder_setting msync)" == true ]]; then
    export WINEMSYNC=1
  elif [[ "$(cyder_setting esync)" == true ]]; then
    export WINEESYNC=1
  fi
}

# 關閉 Cyder shared bottle 內所有 Windows 程式，並等 wineserver 結束（最多 15 秒；之後才能修改 engine）。
wineserver_kill() {
  (
    export_wine_env
    /usr/bin/arch -x86_64 "$WINESERVER_BIN" -k
  ) >/dev/null 2>&1 || true
  wait_until 15 wine_stopped || true
}

# run_wine_tool <exe> [參數...]：在 shared bottle 執行 Wine 內建的主控台程式（reg 等），不輸出 Wine 訊息。
# Wine 原本沒在執行時，等這次啟動的 wineserver 結束（登錄寫回 user.reg）再返回。
run_wine_tool() {
  local was_running=0 rc=0
  wine_running && was_running=1
  (
    export_wine_env
    WINEDEBUG=-all /usr/bin/arch -x86_64 "$WINE_BIN" "$@"
  ) >/dev/null 2>&1 || rc=$?
  ((was_running)) || wait_until 20 wine_stopped || true
  return $rc
}

# session_procs：本專案啟動的 Windows 程式，每行「PID exe 名稱」。
# 以命令列開頭比對：遊戲資料夾的 Windows 路徑（Z:\…，含 BlackCipher、NxOverlay 等子資料夾），
# 或以相對路徑啟動的 HostShield.exe／認證器.exe。不讀取其餘命令列參數。
session_procs() {
  local dir="${GAME_DIR%/}" phys
  phys="$(cd "$dir" 2>/dev/null && pwd -P || echo "$dir")"
  /bin/ps -axo pid=,args= | GAME_WIN="Z:${dir//\//\\}\\" GAME_WIN_PHYS="Z:${phys//\//\\}\\" /usr/bin/awk '
    {
      pid = $1; cmd = $0; sub(/^ *[0-9]+ /, "", cmd); rest = ""
      if (index(cmd, ENVIRON["GAME_WIN"]) == 1) rest = substr(cmd, length(ENVIRON["GAME_WIN"]) + 1)
      else if (index(cmd, ENVIRON["GAME_WIN_PHYS"]) == 1) rest = substr(cmd, length(ENVIRON["GAME_WIN_PHYS"]) + 1)
      else if (cmd ~ /^(HostShield|認證器)\.exe( |$)/) rest = cmd
      else next
      if (!match(rest, /\.([Ee][Xx][Ee]|aes)( |$)/)) next
      name = substr(rest, 1, RSTART + 3); sub(/.*\\/, "", name)
      print pid, name
    }'
}

# foreign_wine_procs：shared bottle 以外或其他遊戲的 Windows 程式 PID（非本專案、非 Wine 系統程式）。
foreign_wine_procs() {
  local ours
  ours=" $(session_procs | /usr/bin/awk '{printf "%s ", $1}')"
  /bin/ps -axo pid=,args= | OURS="$ours" /usr/bin/awk '
    {
      pid = $1; cmd = $0; sub(/^ *[0-9]+ /, "", cmd)
      if (index(ENVIRON["OURS"], " " pid " ")) next
      if (cmd ~ /^[A-Za-z]:\\/ && tolower(cmd) !~ /^c:\\windows\\(system32|syswow64)\\/) print pid
    }'
}

# wait_until <秒數> <指令...>：約每秒檢查一次，直到指令成功（回傳 0）或超過秒數（回傳 1）。
# 以經過時間計算，指令本身耗時也算在內。
wait_until() {
  local end=$((SECONDS + $1))
  shift
  while :; do
    "$@" && return 0
    ((SECONDS < end)) || return 1
    sleep 1
  done
}

sha256() { /usr/bin/shasum -a 256 "$1" | /usr/bin/cut -d' ' -f1; }
