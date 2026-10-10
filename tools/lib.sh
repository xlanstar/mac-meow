# shellcheck shell=bash
# 開發工具共用設定。tools/*.sh 以 `source "$(cd "$(dirname "$0")" && pwd)/lib.sh"` 載入。
# 建立在 scripts/lib/common.sh 之上（路徑、Cyder 設定、wineserver 操作、die、usage、wait_until），另外提供：
#   ROOT / TOOLS_BIN / DEBUG_DIR、load_env、ok、usage_doc、need_cmd、out_dir、maple_pids、need_tool、in_terminal、
#   run_wine、llvm_paths（LLVM 路徑）、nosdk_exe / NOSDK_MSVCRT（不需 SDK 的 Windows 程式）、
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

# ok <訊息>：檢查通過的項目。
ok() { echo "  ✓ $*"; }

# usage_doc：印出呼叫端腳本開頭的註解（第 2 行起，到第一個非註解行為止）並以 64（EX_USAGE）結束。
usage_doc() {
  /usr/bin/awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
  exit 64
}

# need_cmd <指令> <安裝方式>：缺少指令就結束。
need_cmd() { command -v "$1" >/dev/null || die "需要 ${1}（${2}）"; }

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

# 不需 SDK 的 Windows 程式與 tools/src/wincrt/crt0.c 用到的 msvcrt 匯出
# （puts：clang 會把不帶參數的 printf("...\n") 改成 puts）
# shellcheck disable=SC2034  # tools/build.sh、experiments/build.sh 使用
NOSDK_MSVCRT="msvcrt:printf puts strtoul _flushall __getmainargs exit"

# nosdk_exe <來源.c> <輸出.exe> <dll:匯出 匯出...>...：clang-cl 編譯來源 + tools/src/wincrt/crt0.c，
# 依清單以 llvm-dlltool 產生 import lib，lld-link 連結（不連預設函式庫）。中間檔在輸出旁的 obj/<名稱>/。
nosdk_exe() {
  local src="$1" out="$2"
  shift 2
  local name o spec dll sym libs=()
  name="$(basename "$src" .c)"
  o="$(dirname "$out")/obj/$name"
  llvm_paths || return 1
  mkdir -p "$o"
  for spec in "$@"; do
    dll="${spec%%:*}"
    {
      echo "LIBRARY $dll.dll"
      echo EXPORTS
      for sym in ${spec#*:}; do echo "$sym"; done
    } >"$o/$dll.def"
    "$LLVM_BIN/llvm-dlltool" -m i386:x86-64 -d "$o/$dll.def" -l "$o/$dll.lib" || return 1
    libs+=("$o/$dll.lib")
  done
  "$LLVM_BIN/clang-cl" --target=x86_64-pc-windows-msvc /O1 /GS- /c "/Fo$o/" -- "$src" "$ROOT/tools/src/wincrt/crt0.c" || return 1
  "$LLD_BIN/lld-link" /subsystem:console /entry:mainCRTStartup /nodefaultlib "/out:$out" \
    "$o/$name.obj" "$o/crt0.obj" ${libs[@]+"${libs[@]}"}
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
