# shellcheck shell=bash disable=SC2034  # 常數由 source 本檔的腳本使用
# 使用者腳本共用的路徑、常數與函式。由 scripts/*.sh、tools/lib.sh source（MacMeow.app 經由 scripts/play.sh 使用）。
# 只能用 macOS 內建指令（會打包進 MacMeow.app）；也會以 root 執行（setup-loopback.sh），不可依賴使用者環境。
[[ -n "${MACMEOW_COMMON_LOADED:-}" ]] && return 0
MACMEOW_COMMON_LOADED=1

# 以管理員權限執行時 HOME 可能未設定；bash 的 ~ 在 HOME 未設定時改查 passwd。
: "${HOME:=$(cd ~ && pwd)}"

# ---------- 路徑（可用環境變數覆寫；GAME_DIR 見下方「設定」） ----------
CYDER_ENGINE="${CYDER_ENGINE:-$HOME/.cyder/runtime/Engines/wine-x86_64}"
CYDER_ENGINE="${CYDER_ENGINE%/}" # 去掉結尾斜線，供路徑前綴比對（sign-debug.sh 等）
# Cyder 的資料夾與 shared bottle。不用 Cyder 腳本會讀取的 CYDER_SUPPORT、CYDER_PREFIX，避免影響 Cyder 的腳本。
CYDER_SUPPORT_DIR="$HOME/Library/Application Support/Cyder"
CYDER_SETTINGS="$CYDER_SUPPORT_DIR/settings.json"
SHARED_BOTTLE="$CYDER_SUPPORT_DIR/bottles/shared"
WINE_BIN="$CYDER_ENGINE/bin/wine"
WINESERVER_BIN="$CYDER_ENGINE/bin/wineserver"
# 本專案的檔案：scripts/（repo 或 MacMeow.app 的 Resources）與其上層（patches/、tools/）。
MACMEOW_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MACMEOW_ROOT="${MACMEOW_SCRIPTS%/*}"
# MacMeow 自己的設定與記錄（uninstall.sh 整個刪除；App 端路徑見 app/Sources/Services/AppPaths.swift）。
MACMEOW_SUPPORT="$HOME/Library/Application Support/MacMeow"
MACMEOW_LOGS="$HOME/Library/Logs/MacMeow"
MACMEOW_CACHE="$HOME/Library/Caches/MacMeow" # update.sh 下載的新版
MACMEOW_CONFIG="$MACMEOW_SUPPORT/config"     # App 的設定檔（app/Sources/Core/AppConfig.swift）

# ---------- 設定 ----------
# 每行「名稱 預設值 允許值」。值的來源依序為：環境變數 MACMEOW_<名稱>、設定檔的 <名稱>=、預設值；
# 結果存在 MACMEOW_<名稱>。遊戲資料夾同理，但環境變數名稱是 GAME_DIR。
# 從終端機執行時也會沿用 App 的設定；App 端的預設值與選項見 AppConfig.swift。
MACMEOW_SETTINGS="SYNC msync msync|esync|none
GRAPHICS_BACKEND d3dmetal d3dmetal|dxmt
HUD 0 0|1
MAX_FPS unlimited 60|120|144|unlimited
AUTO_CLOSE 1 0|1
HIDE_LAUNCHER_DOCK 0 0|1"

# setting_allowed <名稱> <值>：值是該設定允許的值（GAME_DIR 只要不是空字串）。
setting_allowed() {
  local name _default allowed
  if [[ "$1" == GAME_DIR ]]; then
    [[ -n "$2" ]]
    return
  fi
  while read -r name _default allowed; do
    if [[ "$name" == "$1" ]]; then
      [[ "|$allowed|" == *"|$2|"* ]]
      return
    fi
  done <<<"$MACMEOW_SETTINGS"
  return 1
}

# load_settings：決定各設定的值（載入本檔時執行）。設定檔中的無效值視為未設定（與 App 相同）；
# 環境變數的值由 validate_settings 檢查。
load_settings() {
  local key val var name default _allowed
  if [[ -r "$MACMEOW_CONFIG" ]]; then
    while IFS='=' read -r key val || [[ -n "$key" ]]; do
      setting_allowed "$key" "$val" || continue
      var="MACMEOW_$key"
      [[ "$key" == GAME_DIR ]] && var=GAME_DIR
      [[ -n "${!var:-}" ]] || printf -v "$var" '%s' "$val"
    done <"$MACMEOW_CONFIG"
  fi
  while read -r name default _allowed; do
    var="MACMEOW_$name"
    [[ -n "${!var:-}" ]] || printf -v "$var" '%s' "$default"
  done <<<"$MACMEOW_SETTINGS"
  GAME_DIR="${GAME_DIR:-$HOME/Games/MapleStory}"
  GAME_DIR="${GAME_DIR%/}" # 去掉結尾斜線，供路徑前綴比對（session_procs 等）
}

# validate_settings：有不允許的值就結束。只在要套用設定時呼叫（play.sh、cyder-settings.sh check|apply）。
validate_settings() {
  local name _default allowed var
  while read -r name _default allowed; do
    var="MACMEOW_$name"
    setting_allowed "$name" "${!var}" || die "${var} 只能是 ${allowed}"
  done <<<"$MACMEOW_SETTINGS"
}

# ---------- MacMeow.app 發佈 ----------
# 一鍵更新（update.sh）只從這個 repo 的 Release 下載，且新版必須符合 MACMEOW_REQUIREMENT；
# release.sh 發佈前也以此驗證。App 端的網址在 app/Sources/Services/AppPaths.swift，改 repo 時一起改。
MACMEOW_REPO="xlanstar/mac-meow"
MACMEOW_BUNDLE_ID="tw.macmeow.launcher"
MACMEOW_TEAM_ID="LJJN3L2PS6"
# 官方版的簽章需求（codesign -R，即 Developer ID 的 designated requirement）：Apple 簽發的
# Developer ID Application 憑證、Team ID 與 bundle id 都要符合；只看 TeamIdentifier 欄位可被自簽憑證偽造。
MACMEOW_REQUIREMENT="anchor apple generic and identifier \"$MACMEOW_BUNDLE_ID\" \
and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
and certificate leaf[subject.OU] = \"$MACMEOW_TEAM_ID\""
# Homebrew cask（第三方 tap；cask 範本 packaging/homebrew/macmeow.rb，由 tools/release.sh tap 發佈）。
# homebrew_app 以 <prefix>/Caskroom/<token> 判斷 App 是否由 Homebrew 安裝。
MACMEOW_CASK="macmeow"
MACMEOW_TAP_REPO="xlanstar/homebrew-tap" # brew 的 tap 名稱為 xlanstar/tap
HOMEBREW_PREFIXES=(/opt/homebrew /usr/local)

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

# usage <子指令說明>：輸出用法並以 64（EX_USAGE）結束。
usage() {
  echo "用法：${0##*/} $*" >&2
  exit 64
}

# run_script <腳本> [參數...]：執行 scripts/ 下的其他腳本。
run_script() {
  local script="$1"
  shift
  bash "$MACMEOW_SCRIPTS/$script" "$@"
}

# plist_value <檔案> <keypath>：plist 或 JSON 檔中的值（讀不到時回傳 1）。
plist_value() { /usr/bin/plutil -extract "$2" raw -o - "$1" 2>/dev/null; }

# pid_gone <PID>：程序已結束（供 wait_until 使用）。
pid_gone() { ! kill -0 "$1" 2>/dev/null; }

# homebrew_app <.app>：App 由 Homebrew cask 安裝（update.sh、uninstall.sh 改為提示 brew 指令）。
# 條件：任一 Homebrew prefix 有本 cask 的 Caskroom，且 App 位於該次安裝的 appdir（--appdir；
# 記錄在 Caskroom/<token>/.metadata/config.json，優先序 explicit → env → default）；排除 dist/ 等其他位置的複本。
homebrew_app() {
  local prefix room key dir
  for prefix in "${HOMEBREW_PREFIXES[@]}"; do
    room="$prefix/Caskroom/$MACMEOW_CASK"
    [[ -d "$room" ]] || continue
    dir=""
    for key in explicit env default; do
      dir="$(plist_value "$room/.metadata/config.json" "$key.appdir")" && break
      dir=""
    done
    [[ "$1" == "${dir:-/Applications}/MacMeow.app" ]] && return 0
  done
  return 1
}

# brew_command <upgrade|uninstall> <.app>：App 由 Homebrew 安裝時輸出對應的 brew 指令，否則回傳 1。
brew_command() {
  homebrew_app "$2" || return 1
  echo "brew $1 --cask $MACMEOW_CASK"
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
cyder_setting() { plist_value "$CYDER_SETTINGS" "$1" || true; }

# gptk_complete <GPTK 目錄>：external/libd3dshared.dylib 可讀、external/D3DMetal.framework 存在
# （與 Cyder 的 cyder_d3dmetal_launch_allowed 檢查的檔案相同；tools/run-game.sh 也使用）。
gptk_complete() { [[ -r "$1/external/libd3dshared.dylib" && -d "$1/external/D3DMetal.framework" ]]; }

# d3dmetal_available：Cyder 可以使用 D3DMetal（Apple GPTK）圖形後端。與 Cyder 的 cyder_d3dmetal_launch_allowed 相同：
# macOS 14 以上，且 Cyder 設定安裝的 GPTK（runtime/apple_gptk）或 CrossOver 內建的 GPTK 完整（gptk_complete）。
# 不符合時 Cyder 會把 graphicsBackend=d3dmetal 當成 default 且停用自動選擇，結果是 Wine 內建的 wined3d。
d3dmetal_available() {
  local version major root
  version="$(/usr/bin/sw_vers -productVersion 2>/dev/null)" || return 1
  major="${version%%.*}"
  [[ "$major" =~ ^[0-9]+$ ]] && ((major >= 14)) || return 1
  for root in "$CYDER_SUPPORT_DIR/runtime/apple_gptk" /Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/apple_gptk; do
    gptk_complete "$root" && return 0
  done
  return 1
}

# cyder_profile_id <exe>：Cyder 的 perProfile 設定 key，與 cyder-profile.sh 的 cyder_profile_id_for_path 相同：
# 「profile-」加上 exe 實際路徑（解析符號連結）SHA-256 的前 24 個十六進位字元。exe 不存在時回傳 1。
cyder_profile_id() {
  local canonical digest
  [[ -e "$1" ]] || return 1
  canonical="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")" || return 1
  digest="$(printf '%s' "$canonical" | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }')"
  printf 'profile-%s\n' "${digest:0:24}"
}

# Cyder 已建立 Windows 環境（shared bottle）且 engine 已下載。
cyder_ready() { [[ -f "$SHARED_BOTTLE/system.reg" && -x "$WINE_BIN" ]]; }

# 認證器.exe（VB6）需要的 runtime 已安裝。
vb6_installed() { [[ -f "$SHARED_BOTTLE/drive_c/windows/syswow64/msvbvm60.dll" ]]; }

# progress <id> <訊息>：顯示步驟訊息。MACMEOW_PROGRESS=1（MacMeow.app）時改輸出「@@STEP <id> <訊息>」供 App 解析。
progress() {
  local id="$1"
  shift
  if [[ "${MACMEOW_PROGRESS:-0}" == 1 ]]; then echo "@@STEP $id $*"; else echo "$*"; fi
}

# wineservers：這個 engine 執行中的 wineserver，每行「PID shared|other」（是否為 shared bottle 的 server）。
# 以 lsof 一次讀出程序名稱為 wineserver 者的執行檔（txt）與工作目錄（cwd）：
# - 執行檔必須是本 engine 的 bin/wineserver（實體路徑），排除其他 Wine；不比對命令列，
#   所以參數含 wineserver 路徑的程序（xxd、codesign 等）不會被誤判。
# - 每個 prefix 一個 wineserver，工作目錄為 <tmp>/.wine-<uid>/server-<prefix dev>-<inode>（十六進位），以此辨識 shared bottle。
wineservers() {
  local exe dev ino server=""
  exe="$(cd "$CYDER_ENGINE/bin" 2>/dev/null && pwd -P)/wineserver" || return 0
  read -r dev ino < <(/usr/bin/stat -f '%d %i' "$SHARED_BOTTLE" 2>/dev/null) && server="$(printf '/server-%x-%x' "$dev" "$ino")"
  /usr/sbin/lsof -a -c '/^wineserver$/' -d cwd,txt -Fpfn 2>/dev/null | EXE="$exe" SERVER="$server" /usr/bin/awk '
    function flush() { if (ours) print pid, (shared ? "shared" : "other") }
    /^p/ { flush(); pid = substr($0, 2); ours = shared = 0 }
    /^f/ { fd = substr($0, 2) }
    /^n/ {
      n = substr($0, 2); s = ENVIRON["SERVER"]
      if (fd == "txt" && n == ENVIRON["EXE"]) ours = 1
      if (fd == "cwd" && s != "" && substr(n, length(n) - length(s) + 1) == s) shared = 1
    }
    END { flush() }'
  return 0 # 沒有 wineserver 時 lsof 回傳 1；呼叫端多在 set -o pipefail 下執行
}

# 這個 engine 有任何 wineserver 在執行（不論哪個 bottle）。所有 bottle 共用 engine，修改 engine 前以此檢查。
engine_running() { [[ -n "$(wineservers)" ]]; }
# shared bottle 的 wineserver PID（沒有則輸出空字串）與是否在執行（= 貓貓谷或 shared bottle 內的程式開著）。
wineserver_pid() { wineservers | /usr/bin/awk '$2 == "shared" && !n++ { print $1 }'; }
wine_running() { [[ -n "$(wineserver_pid)" ]]; }
wine_stopped() { ! wine_running; }

# require_wine_stopped <動作說明>：engine 有任何 wineserver 在執行就拒絕修改 engine（所有 bottle 共用）。
require_wine_stopped() {
  engine_running && die "請先關閉所有 Cyder 遊戲（包含貓貓谷）再${1}。"
  return 0
}

# 匯出 Wine client 需要的環境。client 必須與執行中的 wineserver 使用相同同步機制（依 Cyder 設定）。
export_wine_env() {
  export WINEPREFIX="$SHARED_BOTTLE"
  # 與 Cyder 的 wineLocale=zh_TW 相同。Wine 依 locale 決定字碼頁；與 bottle 記錄的不同時（Fonts\Codepages），
  # 任何 Wine 程式啟動都會改寫語系相依的字型設定（FontSubstitutes 的 MS Shell Dlg 等），例如從 LANG=C 的 shell 執行 reg。
  export LANG=zh_TW.UTF-8 LC_ALL=zh_TW.UTF-8
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
# ps 在非 UTF-8 locale（例如 MacMeow.app 啟動的腳本）會把中文跳脫成 M-… 字元，所以固定以 UTF-8 執行；
# awk 以 C locale 逐位元組比對。
session_procs() {
  local dir="${GAME_DIR%/}" phys
  phys="$(cd "$dir" 2>/dev/null && pwd -P || echo "$dir")"
  LC_ALL=en_US.UTF-8 /bin/ps -axo pid=,args= | LC_ALL=C GAME_WIN="Z:${dir//\//\\}\\" GAME_WIN_PHYS="Z:${phys//\//\\}\\" /usr/bin/awk '
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
  LC_ALL=en_US.UTF-8 /bin/ps -axo pid=,args= | LC_ALL=C OURS="$ours" /usr/bin/awk '
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

# dmg_attach [--readonly] [--nobrowse] [--mountpoint <路徑>] <映像>：掛載磁碟映像，輸出格式同 hdiutil attach
# （裝置<TAB>內容<TAB>掛載點）。macOS 26 起 hdiutil attach 已棄用（會印警告），改用 diskutil image attach；
# 沒有 diskutil image 的舊系統退回 hdiutil。diskutil 不會自動建立 --mountPoint 目錄（hdiutil 會），所以先建好。
# diskutil image attach 的文字輸出會把非 ASCII 掛載點以 MacRoman 重複編碼（與 locale 無關），
# 所以改讀 --plist 輸出再轉成 hdiutil 的格式。
dmg_attach() {
  local d=() h=(-noverify -noautoopen) plist i dev hint mp
  while (($# > 1)); do
    case "$1" in
      --readonly) d+=(--readOnly) h+=(-readonly) ;;
      --nobrowse) d+=(--nobrowse) h+=(-nobrowse) ;;
      --mountpoint)
        d+=(--mountPoint "$2") h+=(-mountpoint "$2")
        mkdir -p "$2" || return
        shift
        ;;
      *)
        echo "dmg_attach：未知選項 $1" >&2
        return 2
        ;;
    esac
    shift
  done
  if diskutil image attach --help >/dev/null 2>&1; then
    plist="$(diskutil image attach --plist ${d[@]+"${d[@]}"} "$1")" || return
    i=0
    while dev="$(plutil -extract "system-entities.$i.dev-entry" raw -o - - <<<"$plist" 2>/dev/null)"; do
      hint="$(plutil -extract "system-entities.$i.content-hint" raw -o - - <<<"$plist" 2>/dev/null)" || hint=
      mp="$(plutil -extract "system-entities.$i.mount-point" raw -o - - <<<"$plist" 2>/dev/null)" || mp=
      printf '/dev/%s\t%s\t%s\n' "$dev" "$hint" "$mp"
      i=$((i + 1))
    done
  else
    hdiutil attach "${h[@]}" "$1"
  fi
}

load_settings
