#!/bin/bash
# 讓 macOS 的 lo0 擁有貓貓谷需要的迴路位址（清單見 scripts/lib/common.sh 的 LOOPBACK_IPS）：
#   127.x.x.1      HostShield 各 token 的通道位址。Windows 整段 127/8 都是本機，macOS 預設只有 127.0.0.1。
#   202.80.104.28  登入器在 Windows 上以 netsh 掛到 Loopback，讓 MapleStory.exe 連到登入器的轉發 port；
#                  Wine 的 netsh 是 stub，所以要在 macOS 補上（掛著時本機連不到該官方 IP，與 Windows 相同）。
# 這是本專案唯一需要 root 的步驟。
#
# 用法：
#   sudo bash scripts/setup-loopback.sh install    # 立即生效並開機自動套用
#   sudo bash scripts/setup-loopback.sh uninstall  # 移除
#   bash scripts/setup-loopback.sh status          # 全部位址都在則回傳 0
#   bash scripts/setup-loopback.sh installed       # 有任何位址或 LaunchDaemon 輸出 yes，否則 no（uninstall.sh 判斷是否需要密碼）
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

LABEL="tw.macmeow.loopback"
PLIST="/Library/LaunchDaemons/$LABEL.plist"

need_root() {
  [[ $EUID -eq 0 ]] || die "請用 sudo 執行：sudo bash $0 $1"
}

# 不用 `ifconfig | grep -q`：pipefail 下 grep 提早結束可能讓 ifconfig 收到 SIGPIPE 而誤判。
has_alias() { [[ "$(/sbin/ifconfig lo0)" == *"inet $1 "* ]]; }

cmd_status() {
  local ip missing=0
  for ip in "${LOOPBACK_IPS[@]}"; do
    if has_alias "$ip"; then echo "OK      $ip"; else
      echo "MISSING $ip"
      missing=1
    fi
  done
  if [[ -f "$PLIST" ]]; then echo "LaunchDaemon：已安裝（${PLIST}）"; else echo "LaunchDaemon：未安裝"; fi
  return $missing
}

cmd_installed() {
  local ip
  [[ -f "$PLIST" ]] && {
    echo yes
    return 0
  }
  for ip in "${LOOPBACK_IPS[@]}"; do has_alias "$ip" && {
    echo yes
    return 0
  }; done
  echo no
}

cmd_install() {
  need_root install
  local ip cmd=""
  for ip in "${LOOPBACK_IPS[@]}"; do
    cmd+="/sbin/ifconfig lo0 alias $ip netmask 255.255.255.255 up; "
  done
  cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/sh</string><string>-c</string><string>$cmd</string></array>
  <key>RunAtLoad</key><true/>
</dict>
</plist>
EOF
  chown root:wheel "$PLIST"
  chmod 644 "$PLIST"
  launchctl bootout system "$PLIST" 2>/dev/null || true
  launchctl bootstrap system "$PLIST"
  for ip in "${LOOPBACK_IPS[@]}"; do
    has_alias "$ip" || /sbin/ifconfig lo0 alias "$ip" netmask 255.255.255.255 up
  done
  cmd_status
}

cmd_uninstall() {
  need_root uninstall
  local ip
  launchctl bootout system "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  for ip in "${LOOPBACK_IPS[@]}"; do /sbin/ifconfig lo0 -alias "$ip" 2>/dev/null || true; done
  echo "已移除 lo0 位址與 LaunchDaemon"
}

case "${1:-}" in
  install | uninstall | status | installed) "cmd_$1" ;;
  *)
    echo "用法：$0 install|uninstall|status|installed" >&2
    exit 64
    ;;
esac
