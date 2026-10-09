#!/bin/bash
# 不經 Cyder.app，直接以 Cyder engine 執行完整流程（認證器.exe → … → MapleStory.exe），所有環境變數可控。
# 會先關閉 Cyder shared bottle 內所有 Windows 程式；Ctrl+C 結束時也會關閉。
# 需在 Terminal.app 內執行（GUI 類 Wine 程式在 agent shell／SSH 會卡住）：
#   open -a Terminal tools/run-game.sh   或   bash tools/run-game.sh [模式]
#
# 模式（第一個參數）：
#   plain    （預設）無 trace，用於效能比較
#   trace    記錄等待、例外、DLL 載入（只對 MapleStory.exe 開頻道），並每 0.5 秒記錄 MapleStory 執行緒數與 socket
#   relay    trace + MapleStory.exe 的 API 呼叫（找出各執行緒最後呼叫；量大、干擾時序）
#   virtual  trace + 記憶體保護／配置（查 virtual_mutex 類鎖死）
#   server   trace + 前景 wineserver -d1 協定紀錄（含 suspend_thread 等請求者；量大，只適合短時間重現）
#
# 環境變數：
#   SYNC=msync|esync|none（預設 msync，與 play.sh 相同）  GFX=dxmt|d3dmetal|dxvk|wined3d（預設 d3dmetal，沒有 GPTK 時改用 dxmt）
#     d3dmetal 需要 GPTK（CrossOver 內附或 Cyder 設定安裝），且 Cyder 已把它連結到 engine 的 lib64/apple_gptk
#   WZCACHE=0|1（預設 0：與從 認證器.exe 啟動時相同；1 = Cyder 的 WZ read-ahead 快取）
#   HUD=1（Metal 效能 HUD，顯示 FPS）  WINEDEBUG=...（覆寫頻道）  EXTRA_DEBUG=...（附加頻道）
#   EXTRA_ENV="K=V K2=V2"（額外環境變數）
# 紀錄：debug/run-<時間>/
set -euo pipefail
# shellcheck source=lib.sh
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"

mode="${1:-plain}"
case "$mode" in plain | trace | relay | virtual | server) ;; *) die "未知模式：${mode}（plain|trace|relay|virtual|server）" ;; esac
game_dir_valid "$GAME_DIR" || die "GAME_DIR 不是有效的遊戲資料夾：${GAME_DIR}"

OUT="$(out_dir run)"
LOG="$OUT/wine.log"

# ---------- 環境 ----------
export WINEPREFIX="$CYDER_PREFIX"
export LANG=zh_TW.UTF-8 LC_ALL=zh_TW.UTF-8 LC_CTYPE=zh_TW.UTF-8
unset WINEMSYNC WINEESYNC
case "${SYNC:-msync}" in
  msync) export WINEMSYNC=1 ;;
  esync) export WINEESYNC=1 ;;
  none) ;;
  *) die "SYNC 只能是 msync|esync|none" ;;
esac
GFX_DEFAULT=0
[[ -z "${GFX:-}" ]] && GFX=d3dmetal GFX_DEFAULT=1
case "$GFX" in dxmt | d3dmetal | dxvk | wined3d) ;; *) die "GFX 只能是 dxmt|d3dmetal|dxvk|wined3d" ;; esac
# 與 Cyder 的 cyder_apply_gptk_launch_environment 相同：有 GPTK 時任何後端都帶上這些變數（ntdll 會載入
# libd3dshared.dylib）。只用 Cyder 已建立的 engine 連結，不自行修改 engine。
# 不設 DYLD_FRAMEWORK_PATH：/usr/bin/arch 受 SIP 保護會清掉 DYLD_*，而 libd3dshared 以 @rpath
# （@loader_path）就找得到同目錄的 D3DMetal.framework。
unset CYDER_GPTK_ROOT CX_APPLEGPTK_LIBD3DSHARED_PATH
gptk="$CYDER_ENGINE/lib64/apple_gptk"
if [[ -r "$gptk/external/libd3dshared.dylib" && -d "$gptk/external/D3DMetal.framework" ]]; then
  gptk="$(cd "$gptk" && pwd -P)"
  export CYDER_GPTK_ROOT="$gptk" CX_APPLEGPTK_LIBD3DSHARED_PATH="$gptk/external/libd3dshared.dylib"
elif [[ "$GFX" == d3dmetal && "$GFX_DEFAULT" == 1 ]]; then
  echo "找不到 GPTK（${gptk}），改用 dxmt。" >&2
  GFX=dxmt
elif [[ "$GFX" == d3dmetal ]]; then
  die "找不到 GPTK（${gptk}）：請安裝 CrossOver 或在 Cyder 設定安裝 GPTK，並以 Cyder 啟動一次"
fi
export CX_GRAPHICS_BACKEND="$GFX" CYDER_GRAPHICS_BACKEND="$GFX" CYDER_GRAPHICS_BACKENDS_ROOT="$CYDER_ENGINE"
export CYDER_MAPLESTORY_FILE_CACHE="${WZCACHE:-0}"
export PATH="$CYDER_ENGINE/bin:$PATH"
[[ "${HUD:-0}" == 1 ]] && export MTL_HUD_ENABLED=1
# shellcheck disable=SC2163  # kv 是 K=V 字串
for kv in ${EXTRA_ENV:-}; do export "$kv"; done

# 「程序名:+channel」只對該程序啟用（Wine debug.c parse_options），避免 HostShield／登入器灌爆紀錄。
M=MapleStory.exe
TRACE="+timestamp,+pid,+tid,+process,+loaddll,$M:+winsock,$M:+seh,$M:+thread,$M:+sync,$M:+win,$M:+msgbox"
case "$mode" in
  plain) default_debug="-all" ;;
  trace | server) default_debug="$TRACE" ;;
  relay) default_debug="$TRACE,$M:+relay" ;;
  virtual) default_debug="$TRACE,$M:+virtual" ;;
esac
export WINEDEBUG="${WINEDEBUG:-$default_debug}${EXTRA_DEBUG:+,$EXTRA_DEBUG}"

{
  echo "mode=$mode SYNC=${SYNC:-msync} GFX=$GFX GPTK=${CYDER_GPTK_ROOT:-none} WZCACHE=$CYDER_MAPLESTORY_FILE_CACHE HUD=${HUD:-0}"
  echo "EXTRA_ENV=${EXTRA_ENV:-}"
  echo "WINEDEBUG=$WINEDEBUG"
} | tee "$OUT/env.txt"

# ---------- 啟動 ----------
wineserver_kill
sleep 2
cd "$GAME_DIR"
if [[ "$mode" == server ]]; then
  /usr/bin/arch -x86_64 "$WINESERVER_BIN" -f -d1 2>"$OUT/server.log" &
  sleep 1
fi
/usr/bin/arch -x86_64 "$WINE_BIN" 認證器.exe >"$LOG" 2>&1 &

stop() {
  trap '' INT TERM
  /usr/bin/arch -x86_64 "$WINESERVER_BIN" -k 2>/dev/null || true
  echo
  echo "已停止。紀錄：$OUT"
  exit 0
}
trap stop INT TERM
echo "執行中，紀錄：$OUT"
echo "卡住時先在另一個終端機執行 bash tools/stack.sh，再按 Ctrl+C（會關閉此 bottle 的所有 Windows 程式）。"

# trace 類模式：監看 MapleStory 執行緒數、CPU、狀態與 socket（comm 不含啟動參數）。
while sleep 0.5; do
  [[ "$mode" == plain ]] && continue
  {
    date +%T
    for pid in $(maple_pids); do
      echo "threads=$(/bin/ps -M -p "$pid" 2>/dev/null | /usr/bin/sed 1d | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
      /bin/ps -p "$pid" -o pid=,etime=,pcpu=,state=,comm= || true
      LC_ALL=C /usr/sbin/lsof -nP -a -p "$pid" -iTCP -iUDP 2>/dev/null || true
    done
  } >>"$OUT/net.log"
done
