#!/bin/bash
# 在 macOS 用 Cyder 啟動貓貓谷（原封不動執行 認證器.exe → HostShield → 貓貓TMS登入器 → MapleStory）。
# 只做 macOS 端的環境準備，不修改任何登入器或遊戲檔案。每一步都先檢查，需要時才套用（可重複執行）。
#
# 用法：
#   bash scripts/play.sh            # 檢查環境並啟動
#   bash scripts/play.sh status     # 查看迴路位址、通道與 Wine 程序狀態
#   bash scripts/play.sh status --porcelain   # 機器可讀的 key=value 狀態（MacMeow.app 使用）
#   bash scripts/play.sh stop       # 關閉 Cyder shared bottle 內所有 Windows 程式（含其他 Cyder 遊戲）
# 環境變數：GAME_DIR、CYDER_ENGINE、SYNC=msync|esync|none、GRAPHICS_BACKEND=d3dmetal|dxmt、HUD=0|1、
#           MAX_FPS=60|120|144|unlimited、AUTO_CLOSE=1|0、HIDE_LAUNCHER_DOCK=0|1
# （見 docs/architecture.md）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

SHIELD_RE="^($(
  IFS='|'
  echo "${HOSTSHIELD_IPS[*]}" | /usr/bin/sed 's/\./\\./g'
)):"

# proc_running <exe 名稱>...：本專案的程式（session_procs，限 GAME_DIR）中有任一個在執行。
# 其他 bottle 或其他遊戲資料夾的同名程式（例如別的私服的 MapleStory.exe）不算。
proc_running() {
  session_procs | LC_ALL=C NAMES=" $* " /usr/bin/awk 'index(ENVIRON["NAMES"], " " $2 " ") { found = 1 } END { exit !found }'
}

# 每個 HostShield 位址目前監聽的 port 數；4 個位址都有監聽才算通道建立。
listeners() {
  /usr/sbin/lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | /usr/bin/awk '{print $9}' \
    | /usr/bin/grep -E "$SHIELD_RE" | /usr/bin/cut -d: -f1 | /usr/bin/sort | /usr/bin/uniq -c || true
}
tunnels_up() { [[ "$(listeners | /usr/bin/wc -l | /usr/bin/tr -d ' ')" -eq ${#HOSTSHIELD_IPS[@]} ]]; }

status() {
  echo "== 迴路位址"
  bash "$SCRIPT_DIR/setup-loopback.sh" status || true
  echo "== HostShield 通道監聽（位址：port 數，預期 ${#HOSTSHIELD_IPS[@]} 個位址、各 ${HOSTSHIELD_PORTS}）"
  listeners | /usr/bin/awk '{printf "%-16s %s\n", $2, $1}'
  echo "== Wine 程序"
  # 比照 session_procs：ps 固定以 UTF-8 執行，否則 App（未設 LANG）下中文會被跳脫成 M-… 而比對不到；
  # grep 以 C locale 逐位元組比對，cut 以 UTF-8 依字元截斷，避免切斷中文。
  LC_ALL=en_US.UTF-8 /bin/ps -axo pid=,command= \
    | LC_ALL=C /usr/bin/grep -E '(認證器|HostShield|貓貓TMS登入器|MapleStory)\.exe|BlackCipher|BlackXchg' \
    | LC_ALL=C /usr/bin/grep -vE 'grep|cyder_launcher|CyderSwift' | LC_ALL=en_US.UTF-8 /usr/bin/cut -c1-160 || true
  echo "== 自動收尾與 Dock"
  bash "$SCRIPT_DIR/session.sh" status || true
  bash "$SCRIPT_DIR/patch-cyder-winemac.sh" check || true
  bash "$SCRIPT_DIR/launcher-dock.sh" status 2>/dev/null || true
}

flag() { if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
patches_applied() {
  bash "$SCRIPT_DIR/patch-cyder-loopback.sh" check && bash "$SCRIPT_DIR/patch-cyder-dlls.sh" check
}

# MacMeow.app 讀取的狀態；新增 key 時同步更新 app/Sources/Status.swift。
porcelain() {
  local missing
  missing="$(missing_game_file "$GAME_DIR" || true)"
  echo "cyder=$(find_cyder || true)"
  echo "cyder_ready=$(flag cyder_ready)"
  echo "game_dir=$GAME_DIR"
  echo "game_dir_valid=$(flag game_dir_valid "$GAME_DIR")"
  echo "missing_file=$missing"
  echo "loopback=$(flag bash "$SCRIPT_DIR/setup-loopback.sh" status)"
  echo "patched=$(flag patches_applied)"
  echo "vb6=$(flag vb6_installed)"
  echo "d3dmetal=$(flag d3dmetal_available)"
  echo "wine=$(flag wine_running)"
  echo "helpers=$(flag proc_running 認證器.exe HostShield.exe)"
  echo "launcher=$(flag proc_running "$LAUNCHER_EXE")"
  echo "game=$(flag proc_running MapleStory.exe)"
  echo "launcher_pid=$(session_procs | LAUNCHER="$LAUNCHER_EXE" /usr/bin/awk '$2 == ENVIRON["LAUNCHER"] { print $1; exit }')"
  echo "watching=$(flag bash "$SCRIPT_DIR/session.sh" status)"
  echo "dock_patched=$(flag bash "$SCRIPT_DIR/patch-cyder-winemac.sh" check)"
  echo "tunnels=$(listeners | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
  echo "tunnels_total=${#HOSTSHIELD_IPS[@]}"
}

case "${1:-}" in
  status)
    if [[ "${2:-}" == --porcelain ]]; then porcelain; else status; fi
    exit 0
    ;;
  stop)
    echo "關閉 Cyder 內所有 Windows 程式 ..."
    wineserver_kill
    wine_stopped || die "Wine 仍在執行，請稍後再試或在 Cyder 中結束。"
    bash "$SCRIPT_DIR/session.sh" cleanup >/dev/null 2>&1 || true
    echo "已全部關閉"
    exit 0
    ;;
  "") ;;
  *)
    echo "用法：$0 [status [--porcelain]|stop]" >&2
    exit 64
    ;;
esac

# 1. 前置條件
progress check "檢查環境 ..."
CYDER="$(find_cyder)" || die "找不到 Cyder.app，請先安裝到 /Applications"
CYDER_SCRIPTS="$CYDER/Contents/Resources/ogom-scripts"
[[ "$CYDER" == "$HOME/Downloads/"* ]] && echo "提示：建議把 Cyder.app 移到 /Applications（避免 App Translocation）"
if f="$(missing_game_file "$GAME_DIR")"; then
  die "缺少 ${GAME_DIR}/${f}（請把登入器壓縮檔內容解到遊戲資料夾）"
fi
bash "$SCRIPT_DIR/setup-loopback.sh" status >/dev/null \
  || die "lo0 尚未加上貓貓谷位址，請先執行：sudo bash ${SCRIPT_DIR}/setup-loopback.sh install"
cyder_ready || die "Cyder prefix 尚未初始化，請先開啟一次 Cyder"

# 遊戲結束時自動關閉登入器與背景程式（session.sh；AUTO_CLOSE=0 時不監看）。
start_watcher() {
  [[ "${AUTO_CLOSE:-1}" == 1 ]] || return 0
  bash "$SCRIPT_DIR/session.sh" start || echo "注意：無法啟動遊戲階段監看，遊戲關閉後請按「全部關閉」" >&2
}

# 2. 前一次留下的程序：登入器或遊戲還在就不重複啟動；只剩 認證器／HostShield 殘留時，只結束本專案的程式
#    （session.sh close）。shared bottle 內其他 Cyder 遊戲不受影響。
if proc_running "$LAUNCHER_EXE" MapleStory.exe; then
  echo "貓貓谷已在執行中（登入器或遊戲視窗仍開著）"
  start_watcher
  exit 0
fi
if proc_running 認證器.exe HostShield.exe; then
  progress cleanup "關閉前一次殘留的 認證器／HostShield ..."
  bash "$SCRIPT_DIR/session.sh" close
fi

# 3. Cyder engine 修補（Wine 執行中會拒絕套用）
#    wineserver：關閉 127.x bind→127.0.0.1 改寫（否則 4 個 HostShield 互搶 port 全部退出）
#    DLL：wsock32（recv hook 無限遞迴凍結）、advapi32（rsaenh 常駐，避免遊戲內 <1 FPS）
progress patch "檢查 Cyder engine 修補 ..."
bash "$SCRIPT_DIR/patch-cyder-loopback.sh" check >/dev/null 2>&1 || bash "$SCRIPT_DIR/patch-cyder-loopback.sh" apply
bash "$SCRIPT_DIR/patch-cyder-dlls.sh" check >/dev/null 2>&1 || bash "$SCRIPT_DIR/patch-cyder-dlls.sh" apply
#    winemac：讓登入器可以不顯示在 Dock（實驗性，預設關閉：會讓遊戲與登入伺服器斷線，
#    見 docs/technical-notes.md #10）。關閉時把先前套用的修補還原。
if [[ "${HIDE_LAUNCHER_DOCK:-0}" == 1 ]]; then
  bash "$SCRIPT_DIR/patch-cyder-winemac.sh" check >/dev/null 2>&1 \
    || bash "$SCRIPT_DIR/patch-cyder-winemac.sh" apply || echo "注意：無法套用 winemac 修補，登入器會照常顯示在 Dock"
elif bash "$SCRIPT_DIR/patch-cyder-winemac.sh" check >/dev/null 2>&1 && ! engine_running; then
  bash "$SCRIPT_DIR/patch-cyder-winemac.sh" restore
fi

# 4. 認證器.exe 是 VB6 程式，需要 VB6 runtime
if ! vb6_installed; then
  require_wine_stopped "安裝 VB6 runtime"
  [[ -f "$CYDER_SCRIPTS/cyder-winetricks.sh" ]] \
    || die "找不到 Cyder 的 winetricks（${CYDER_SCRIPTS}/cyder-winetricks.sh），Cyder 版本可能不相容"
  progress vb6 "安裝 VB6 runtime（vb6run，約 1–2 分鐘）..."
  bash "$CYDER_SCRIPTS/cyder-winetricks.sh" install vb6run
fi

# 4b. 登入器的 Dock 圖示（Wine 登錄；需要 patch-cyder-winemac.sh 的修補才有作用）
if [[ "${HIDE_LAUNCHER_DOCK:-0}" == 1 ]]; then
  bash "$SCRIPT_DIR/launcher-dock.sh" status >/dev/null 2>&1 || {
    progress settings "設定登入器不顯示在 Dock ..."
    bash "$SCRIPT_DIR/launcher-dock.sh" hide || echo "注意：無法設定登入器的 Dock 圖示"
  }
else
  bash "$SCRIPT_DIR/launcher-dock.sh" status >/dev/null 2>&1 && {
    progress settings "恢復登入器的 Dock 圖示 ..."
    bash "$SCRIPT_DIR/launcher-dock.sh" show || echo "注意：無法恢復登入器的 Dock 圖示"
  }
fi

# 5. Cyder 設定（wineLocale、圖形後端、效能 HUD、FPS 上限、同步機制；原值備份，uninstall.sh 還原）
progress settings "檢查 Cyder 設定 ..."
bash "$SCRIPT_DIR/cyder-settings.sh" apply # 已符合時不修改

# 6. 移除 macOS 下載隔離標記（只動 xattr，不動檔案內容；原標記記錄下來，uninstall.sh 加回）
bash "$SCRIPT_DIR/quarantine.sh" clear || echo "注意：無法移除遊戲資料夾的下載隔離標記"

# 7. 照官方教學：從「認證器」啟動，等待 HostShield 通道
progress launch "啟動 認證器.exe ..."
/usr/bin/open -n -a "$CYDER" "$GAME_DIR/認證器.exe"
progress tunnels "等待 HostShield 通道建立（最多 60 秒）..."
if wait_until 60 tunnels_up; then
  echo "通道已建立："
  status
  start_watcher
  exit 0
fi
echo "60 秒內沒看到全部通道監聽，請執行 bash scripts/play.sh status 檢查" >&2
status
start_watcher
exit 1
