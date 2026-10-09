# shellcheck shell=bash
# 開發工具共用設定。tools/*.sh 以 `source "$(dirname "$0")/lib.sh"` 載入。
# 建立在 scripts/lib/common.sh 之上（路徑、Cyder 設定、wineserver 操作），另外提供：
#   ROOT / TOOLS_BIN / DEBUG_DIR、load_env、out_dir、maple_pids、need_tool、in_aqua_terminal、run_wine、llvm 路徑、
#   APP_SWIFT_TARGET / app_sources（App 原始碼）
[[ -n "${MACMEOW_TOOLS_LOADED:-}" ]] && return 0
MACMEOW_TOOLS_LOADED=1

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib/common.sh
source "$ROOT/scripts/lib/common.sh"

TOOLS_BIN="$ROOT/build/tools" # tools/build.sh 的產物
DEBUG_DIR="$ROOT/debug"       # 所有診斷輸出（.gitignore）
# shellcheck disable=SC2034  # build-app.sh、release.sh 使用
APP_SWIFT_TARGET="arm64-apple-macos13.0" # App 的 swiftc target；與 Info.plist 的 LSMinimumSystemVersion 一致

# load_env：載入 repo 根目錄的 .env（本機設定，不提交；範本見 .env.example）。
# 格式為每行 KEY=VALUE（可加 export、引號、# 註解）；已存在的環境變數優先，不會被覆蓋。
load_env() {
  local f="$ROOT/.env" line key val
  [[ -f "$f" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
    key="${BASH_REMATCH[2]}"
    val="${BASH_REMATCH[3]}"
    if [[ "$val" =~ ^\"([^\"]*)\"[[:space:]]*(#.*)?$ || "$val" =~ ^\'([^\']*)\'[[:space:]]*(#.*)?$ ]]; then
      val="${BASH_REMATCH[1]}"
    else
      val="${val%%[[:space:]]#*}"          # 去掉未加引號值後的註解
      val="${val%"${val##*[![:space:]]}"}" # 去掉結尾空白
    fi
    [[ -n "${!key+x}" ]] && continue
    export "$key=$val"
  done <"$f"
}

# out_dir <prefix>：建立 debug/<prefix>-<時間> 並輸出路徑（權限只限本人）。
out_dir() {
  local d
  d="$DEBUG_DIR/$1-$(date +%Y%m%d-%H%M%S)"
  (
    umask 077
    mkdir -p "$d"
  )
  echo "$d"
}

# 執行中的 MapleStory.exe PID（以 comm 比對，不讀取命令列參數，避免碰到帳號資訊）。
maple_pids() {
  /bin/ps -axo pid=,comm= | /usr/bin/awk '/[Mm]aple[Ss]tory\.exe$/ {print $1}'
}

# need_tool <名稱...>：確保 build/tools 下的工具存在，否則先建置。
need_tool() {
  local t missing=()
  for t in "$@"; do [[ -x "$TOOLS_BIN/$t" ]] || missing+=("$t"); done
  ((${#missing[@]} == 0)) || bash "$ROOT/tools/build.sh" "${missing[@]}"
}

# 設定 LLVM_BIN／LLD_BIN／BISON_BIN（Homebrew：brew install llvm lld bison）；缺少時回傳 1。
llvm_paths() {
  local brew
  brew="$(brew --prefix 2>/dev/null || echo /opt/homebrew)"
  LLVM_BIN="${LLVM_BIN:-$brew/opt/llvm/bin}"
  LLD_BIN="${LLD_BIN:-$brew/opt/lld/bin}"
  # shellcheck disable=SC2034  # build-wine-dlls.sh 使用
  BISON_BIN="$brew/opt/bison/bin"
  [[ -x "$LLVM_BIN/clang" && -x "$LLD_BIN/lld-link" ]] || {
    echo "缺少 Homebrew LLVM／lld（brew install llvm lld bison）" >&2
    return 1
  }
  export LLVM_BIN LLD_BIN
}

# in_terminal <timeout 秒> <指令...>：在新的 Terminal.app 視窗執行指令並等待完成，印出其輸出、回傳其結束碼。
# GUI 類 Wine 程式從 agent shell／SSH 啟動會卡在 Cocoa 初始化；Terminal.app 是可靠的 Aqua 工作階段。
# （launchctl managername、TERM_PROGRAM 在 agent shell 內也可能顯示 Aqua，無法用來判斷。）
in_terminal() {
  local timeout="$1"
  shift
  local tmp rc
  tmp="$(mktemp -d /tmp/macmeow-term.XXXXXX)" # 路徑只含 ASCII，可直接放進 AppleScript 字串
  # 指令寫成腳本檔交給 bash 執行，避免參數經過 AppleScript 與 Terminal 預設 shell（zsh）兩層跳脫。
  {
    echo '#!/bin/bash'
    printf '%q ' "$@"
    echo '>"$(dirname "$0")/out" 2>&1'
    echo 'echo $? >"$(dirname "$0")/rc"'
  } >"$tmp/run.sh"
  /usr/bin/osascript -e "tell application \"Terminal\" to do script \"/bin/bash $tmp/run.sh; exit\"" >/dev/null
  wait_until "$timeout" test -f "$tmp/rc" || {
    echo "Terminal 內的指令 ${timeout} 秒內未完成：$*" >&2
    rm -rf "$tmp"
    return 124
  }
  sleep 0.2
  cat "$tmp/out"
  rc="$(cat "$tmp/rc")"
  rm -rf "$tmp"
  return "${rc:-1}"
}

# run_wine <exe> [參數...]：在 Cyder shared bottle 內執行（與遊戲共用 wineserver）。
run_wine() {
  export_wine_env
  WINEDEBUG="${WINEDEBUG:--all}" /usr/bin/arch -x86_64 "$WINE_BIN" "$@"
}

# app_sources [子資料夾...]：把 app/Sources（或其下的子資料夾）內所有 .swift（含子資料夾，排序）讀進 APP_SOURCES 陣列。
app_sources() {
  local dir f
  APP_SOURCES=()
  for dir in "${@:-.}"; do
    while IFS= read -r f; do APP_SOURCES+=("$f"); done < <(find "$ROOT/app/Sources/$dir" -name '*.swift' | sort)
  done
}
