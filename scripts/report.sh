#!/bin/bash
# 產生問題回報用的診斷資訊（MacMeow.app 的「回報問題」使用，也可手動執行後貼到 GitHub issue）。
# 輸出一律隱藏家目錄與使用者名稱；不讀取遊戲資料夾內的 login.txt 或任何帳號資料。
#
# 用法：
#   bash scripts/report.sh                         # 環境摘要（Markdown）
#   bash scripts/report.sh log <記錄檔> [行數]      # 記錄檔最後幾行（預設 40）
#   bash scripts/report.sh bundle <輸出.zip> [記錄檔]   # 診斷檔：摘要、狀態、記錄、MacMeow 當機報告
# 環境變數：MACMEOW_VERSION（App 版本；未設定時讀 repo 的 VERSION），以及 common.sh 的設定與路徑
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

# 隱藏家目錄、任何 /Users/<名稱>，以及 HostShield 的通道 token（程序參數）。
# 使用者名稱也會單獨出現（例如 lsof 的 USER 欄）；太短的名稱容易誤傷一般文字，只取代 3 個字元以上的。
redact() {
  local home="${HOME%/}" user args=()
  user="$(/usr/bin/id -un)"
  [[ ${#user} -ge 3 ]] && args=(-e "s/[[:<:]]${user}[[:>:]]/<user>/g")
  /usr/bin/sed -e "s|${home}|~|g" -E -e 's|/Users/[^/[:space:]"]+|/Users/<user>|g' \
    -e 's/(HostShield\.exe["'"'"']?[[:space:]]+)[^[:space:]]+/\1<token>/g' ${args[@]+"${args[@]}"}
}

app_version() {
  if [[ -n "${MACMEOW_VERSION:-}" ]]; then
    echo "$MACMEOW_VERSION"
  elif [[ -f "$MACMEOW_ROOT/VERSION" ]]; then
    echo "$(cat "$MACMEOW_ROOT/VERSION")（原始碼）"
  else echo "未知"; fi
}

# settings_summary：目前生效的設定（common.sh 的 load_settings），「名稱=值」以空白分隔。
settings_summary() {
  local name _rest var out=""
  while read -r name _rest; do
    var="MACMEOW_$name"
    out+="$name=${!var} "
  done <<<"$MACMEOW_SETTINGS"
  echo "${out% }"
}

# plist_or_unknown <檔案> <keypath>：同 plist_value，讀不到時輸出「?」。
plist_or_unknown() { plist_value "$1" "$2" || echo "?"; }

summary() {
  local cyder engine_manifest="$CYDER_ENGINE/engine-manifest.json" mem missing exe
  echo "- MacMeow：$(app_version)"
  echo "- macOS：$(/usr/bin/sw_vers -productVersion)（$(/usr/bin/sw_vers -buildVersion)）"
  mem=$(($(/usr/sbin/sysctl -n hw.memsize) / 1073741824))
  echo "- 晶片：$(/usr/sbin/sysctl -n machdep.cpu.brand_string)，記憶體 ${mem} GB"
  if [[ -e /Library/Apple/usr/share/rosetta/rosetta ]]; then echo "- Rosetta 2：已安裝"; else echo "- Rosetta 2：未安裝"; fi
  if cyder="$(find_cyder)"; then
    echo "- Cyder：$(plist_or_unknown "$cyder/Contents/Info.plist" CFBundleShortVersionString)（${cyder%/Cyder.app}）"
  else
    echo "- Cyder：未安裝"
  fi
  if [[ -f "$engine_manifest" ]]; then
    echo "- Engine：$(plist_or_unknown "$engine_manifest" versionLabel)（CrossOver $(plist_or_unknown "$engine_manifest" base.crossover)、Wine $(plist_or_unknown "$engine_manifest" base.wine)）"
  else
    echo "- Engine：未下載"
  fi
  echo "- Cyder 設定：wineLocale=$(cyder_setting wineLocale) graphicsBackend=$(cyder_setting graphicsBackend) graphicsHud=$(cyder_setting graphicsHud) dxvkFrameRate=$(cyder_setting dxvkFrameRate) msync=$(cyder_setting msync) esync=$(cyder_setting esync)"
  echo "- MacMeow 設定：$(settings_summary)"
  echo "- 可用的圖形後端：$(available_graphic_backends)"
  if missing="$(missing_game_file "$GAME_DIR")"; then
    echo "- 遊戲資料夾：缺少 ${missing}"
  else
    exe="$GAME_DIR/MapleStory.exe"
    echo "- MapleStory.exe：$(/usr/bin/stat -f %z "$exe") bytes，sha256 $(sha256 "$exe" | /usr/bin/cut -c1-16)"
  fi
  echo "- 修補：$({
    run_script patch-cyder-loopback.sh check
    run_script patch-cyder-dlls.sh check
    run_script patch-cyder-winemac.sh check
    run_script launcher-dock.sh check
  } 2>&1 \
    | /usr/bin/paste -sd '|' - | /usr/bin/sed 's/|/，/g')"
  echo "- 狀態：$(run_script play.sh status --porcelain 2>/dev/null \
    | /usr/bin/grep -vE '^(cyder|game_dir|missing_file)=' | /usr/bin/paste -sd ' ' -)"
}

log_tail() {
  [[ -f "$1" ]] || {
    echo "（沒有記錄檔）"
    return 0
  }
  /usr/bin/tail -n "${2:-40}" "$1"
}

bundle() {
  local out="$1" log="${2:-}" work dir f
  [[ "$out" == *.zip ]] || die "輸出檔名需為 .zip"
  work="$(/usr/bin/mktemp -d)"
  # shellcheck disable=SC2064
  trap "/bin/rm -rf '$work'" EXIT
  dir="$work/$(basename "$out" .zip)"
  /bin/mkdir -p "$dir"
  summary | redact >"$dir/summary.md"
  run_script play.sh status 2>&1 | redact >"$dir/status.txt" || true
  [[ -n "$log" && -f "$log" ]] && /usr/bin/tail -n 5000 "$log" | redact >"$dir/launcher.log"
  [[ -f "$MACMEOW_LOGS/session.log" ]] && /usr/bin/tail -n 2000 "$MACMEOW_LOGS/session.log" | redact >"$dir/session.log"
  # 最近 7 天 MacMeow.app 自己的當機報告
  while IFS= read -r f; do
    redact <"$f" >"$dir/${f##*/}"
  done < <(/usr/bin/find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'MacMeow*' -mtime -7 2>/dev/null)
  /bin/mkdir -p "$(dirname "$out")"
  /bin/rm -f "$out"
  /usr/bin/ditto -c -k --norsrc --noextattr --keepParent "$dir" "$out"
  echo "$out"
}

USAGE="[log <記錄檔> [行數]|bundle <輸出.zip> [記錄檔]]"
case "${1:-}" in
  "") summary | redact ;;
  log)
    (($# >= 2)) || usage "$USAGE"
    log_tail "$2" "${3:-40}" | redact
    ;;
  bundle)
    (($# >= 2)) || usage "$USAGE"
    bundle "$2" "${3:-}"
    ;;
  *) usage "$USAGE" ;;
esac
