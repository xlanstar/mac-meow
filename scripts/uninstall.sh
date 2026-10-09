#!/bin/bash
# 移除本專案對系統與 Cyder 所做的所有變更（不刪除遊戲、Cyder 或其設定）：
#   1. 還原 Cyder engine：wineserver（loopback 修補）、wsock32.dll／advapi32.dll、winemac.so（Dock 圖示）、
#      開發用除錯簽章（只在 repo 內執行時；App 不打包 tools/）；刪除 shared bottle 登錄中登入器的 Dock 圖示設定
#   2. 還原 Cyder 全域設定的原值，加回遊戲資料夾的下載隔離標記
#   3. 移除 lo0 位址與 LaunchDaemon（需要管理員密碼；只有這一步以 root 執行 setup-loopback.sh）
#   4. 刪除 MacMeow.app 的設定與記錄
# 只用 macOS 內建指令（打包進 MacMeow.app，App 的「解除安裝⋯」與 Homebrew cask 都呼叫打包的這一份）。
#
# 用法：
#   bash scripts/uninstall.sh                  # 1–3，全部成功才 4
#   uninstall.sh cask                          # Homebrew cask 的 uninstall script：brew upgrade／reinstall／install
#                                              # 也會執行 cask 的 uninstall 區塊，這時什麼都不做；其餘同上
#   uninstall.sh system                        # 1–3（App 用；App 結束後再 purge）
#   uninstall.sh stage                         # 把 purge 需要的檔案複製到暫存資料夾並輸出其中 uninstall.sh 的路徑
#                                              # （App 隨後被移到垃圾桶，而 ~/.Trash 受隱私權保護，App 無法從那裡執行）
#   uninstall.sh purge [<App PID>]             # 4；有 PID 時先等該程序結束（App 結束時會再寫入偏好設定）
#   uninstall.sh brew-command <目前的 .app>    # App 由 Homebrew 安裝時輸出移除指令並回傳 0，否則回傳 1
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

STAGE_PREFIX="macmeow-uninstall."

usage() { die "用法：uninstall.sh [cask|system|stage|purge [<App PID>]|brew-command <目前的 .app>]"; }

# shellcheck disable=SC2329  # 由 wait_until 呼叫
pid_gone() { ! kill -0 "$1" 2>/dev/null; }

# 在終端機前景執行（sudo 才能讀密碼；背景 process group 讀 tty 會被 SIGTTIN 停住）。
in_terminal_foreground() {
  local tpgid pgid
  [[ -t 0 ]] || return 1
  read -r tpgid pgid < <(/bin/ps -o tpgid=,pgid= -p $$ 2>/dev/null) || return 1
  [[ -n "$tpgid" && "$tpgid" == "$pgid" ]]
}

# 以 root 執行 setup-loopback.sh uninstall。終端機前景用 sudo；其他情況（App、Homebrew 的子程序不在前景
# process group、背景執行）改用系統的密碼對話框。
remove_loopback() {
  local script="$ROOT/scripts/setup-loopback.sh" state
  state="$(bash "$script" installed)" || state=""
  case "$state" in
    no)
      echo "本機網路位址與 LaunchDaemon：未安裝"
      return 0
      ;;
    yes) ;;
    *)
      echo "無法判斷本機網路位址的狀態（${script}）" >&2
      return 1
      ;;
  esac
  echo "移除 lo0 位址與 LaunchDaemon（需要管理員密碼）："
  if in_terminal_foreground; then
    sudo bash "$script" uninstall
  elif ! /usr/bin/osascript \
    -e 'on run argv' \
    -e 'do shell script "/bin/bash " & quoted form of (item 1 of argv) & " uninstall" with prompt "貓貓谷 for Mac 要移除本機網路位址與開機設定。" with administrator privileges' \
    -e 'end run' "$script"; then
    echo "沒有移除本機網路位址（可能取消了密碼輸入）。請再執行一次，或在「終端機」執行以下指令後再執行一次：" >&2
    echo "  sudo bash '${script}' uninstall" >&2
    return 1
  fi
}

# 還原 engine、Cyder 設定、隔離標記與 loopback（1–3）。部分失敗時繼續其他步驟，最後回傳 1。
cmd_system() {
  local rc=0
  require_wine_stopped "執行移除"
  bash "$ROOT/scripts/launcher-dock.sh" show || rc=1
  bash "$ROOT/scripts/patch-cyder-loopback.sh" restore || rc=1
  bash "$ROOT/scripts/patch-cyder-dlls.sh" restore || rc=1
  bash "$ROOT/scripts/patch-cyder-winemac.sh" restore || rc=1
  # 除錯簽章是開發工具，只會由 repo 內的 tools/sign-debug.sh 套用；App 內沒有這個檔案
  if [[ -f "$ROOT/tools/sign-debug.sh" ]]; then
    bash "$ROOT/tools/sign-debug.sh" restore || rc=1
  fi
  bash "$ROOT/scripts/cyder-settings.sh" restore || rc=1
  # 記錄在 MACMEOW_SUPPORT，必須在 purge 刪除它之前還原
  bash "$ROOT/scripts/quarantine.sh" restore || rc=1
  remove_loopback || rc=1
  return $rc
}

# 輸出暫存資料夾內 uninstall.sh 的路徑；purge 會刪除這個資料夾。
cmd_stage() {
  local dir tmp="${TMPDIR:-/tmp}"
  dir="$(/usr/bin/mktemp -d "${tmp%/}/${STAGE_PREFIX}XXXXXX")"
  mkdir -p "$dir/scripts/lib"
  install -m 755 "$ROOT/scripts/uninstall.sh" "$dir/scripts/uninstall.sh"
  install -m 644 "$ROOT/scripts/lib/common.sh" "$dir/scripts/lib/common.sh"
  echo "$dir/scripts/uninstall.sh"
}

# 刪除 MacMeow.app 的設定與記錄（4）。
cmd_purge() {
  if (($# == 1)); then
    # App 啟動後隨即結束；不再有人讀取輸出
    exec </dev/null >/dev/null 2>&1
    wait_until 300 pid_gone "$1" || true
  fi
  rm -rf "$MACMEOW_SUPPORT" "$MACMEOW_LOGS" "$MACMEOW_CACHE" \
    "$HOME/Library/Saved Application State/$MACMEOW_BUNDLE_ID.savedState"
  # SwiftUI 視窗位置與檢查更新設定（tw.macmeow.launcher 偏好設定）
  /usr/bin/defaults delete "$MACMEOW_BUNDLE_ID" >/dev/null 2>&1 || true
  echo "已刪除 MacMeow.app 的設定與記錄"
  # 由 stage 複製出來執行時刪除自己（整段已讀進記憶體）
  [[ "$(basename "$ROOT")" != "$STAGE_PREFIX"* ]] || rm -rf "$ROOT"
}

# system 有任何步驟失敗就不 purge：quarantine.macmeow-orig 等還原記錄在 MACMEOW_SUPPORT，
# 刪掉後再執行一次也無法還原。
cmd_all() {
  if ! cmd_system; then
    echo "部分步驟失敗，請檢查上方訊息後重新執行（已完成的步驟不會重複）。" >&2
    return 1
  fi
  cmd_purge
  echo "完成。"
}

# brew_subcommand：往上找最近的 Homebrew 程序（…/Library/Homebrew/brew.rb <子指令> …），輸出子指令。
# brew.sh 把子指令（已把 rm、remove 等別名換成 uninstall）放在 brew.rb 的第一個參數。找不到時回傳 1。
brew_subcommand() {
  local pid="$PPID" args sub
  while ((pid > 1)); do
    args="$(/bin/ps -o args= -p "$pid" 2>/dev/null)" || return 1
    if [[ "$args" == */Library/Homebrew/brew.rb\ * ]]; then
      read -r sub _ <<<"${args#*/Library/Homebrew/brew.rb }"
      [[ -n "$sub" ]] || return 1
      echo "$sub"
      return 0
    fi
    pid="$(/bin/ps -o ppid= -p "$pid" 2>/dev/null | /usr/bin/tr -d ' ')" || return 1
    [[ -n "$pid" ]] || return 1
  done
  return 1
}

# Homebrew 升級或重裝時也會執行 cask 的 uninstall 區塊（新版 App 隨即裝回），這時保留所有修補與設定。
# 判斷不出來時當作移除：誤判的代價是還原修補、刪除 App 的設定（遊戲資料夾、Wine 設定）並要求密碼，
# 下次開始遊戲時要重新選擇與套用；反過來漏還原則會在 App 移除後留下修改過的 engine，所以寧可多做。
cmd_cask() {
  local sub
  sub="$(brew_subcommand)" || sub=""
  case "$sub" in
    upgrade | reinstall | install)
      echo "brew ${sub}：保留 MacMeow 的修補與設定"
      return 0
      ;;
  esac
  cmd_all
}

# 整段先讀完再執行：purge 會刪除 stage 出來的這份腳本。
{
  case "${1:-}" in
    "") cmd_all ;;
    cask) cmd_cask ;;
    system) cmd_system ;;
    stage) cmd_stage ;;
    purge)
      shift
      (($# <= 1)) || usage
      cmd_purge "$@"
      ;;
    brew-command)
      (($# == 2)) || usage
      homebrew_app "$2" || exit 1
      echo "brew uninstall --cask $MACMEOW_CASK"
      ;;
    *) usage ;;
  esac
  exit
}
