#!/bin/bash
# 以 patches/bin/x86_64-windows/ 的修補版 Wine DLL 取代 Cyder engine 內建版（docs/technical-notes.md #6、#7）：
#   wsock32.dll   patches/wsock32-distinct-recv.patch：wsock32!recv 獨立化，避免 recv hook 無限遞迴（遊戲凍結）
#   advapi32.dll  patches/advapi32-pin-csp.patch：CSP（rsaenh.dll）載入後常駐，避免反覆重新映射（嚴重卡頓）
# DLL 由 CrossOver 26.3.0（REQUIRED_BASE）原始碼建置（tools/build-wine-dlls.sh），只套用到同一基底版本的 engine。
#
# 用法：bash scripts/patch-cyder-dlls.sh check|apply|restore
#   check    全部已套用則回傳 0
#   apply    套用；原檔備份為 *.macmeow-orig，並以 *.macmeow-applied 記錄裝上去的檔案雜湊
#   restore  還原並刪除備份（engine 已更新時只刪除過期備份）
set -euo pipefail
# shellcheck source=lib/common.sh
source "$(cd "$(dirname "$0")" && pwd)/lib/common.sh"

SRC_DIR="$MACMEOW_ROOT/patches/bin/x86_64-windows"
SUMS="$MACMEOW_ROOT/patches/bin/SHA256SUMS"
DST_DIR="$CYDER_ENGINE/lib/wine/x86_64-windows"
REQUIRED_BASE="26.3.0"

engine_base() { plist_value "$CYDER_ENGINE/engine-manifest.json" base.crossover || echo unknown; }

# 修補 DLL 必須與 SHA256SUMS 相符（避免套用損毀或未登記的建置）。
verify_sources() {
  (cd "$SRC_DIR" && /usr/bin/shasum -a 256 -s -c "$SUMS") || die "修補 DLL 與 ${SUMS} 不符，不套用。"
}

cmd_check() {
  local src name dst rc=0
  for src in "$SRC_DIR"/*.dll; do
    name="${src##*/}"
    dst="$DST_DIR/$name"
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then echo "${name}：已套用"; else
      echo "${name}：未套用"
      rc=1
    fi
  done
  return $rc
}

cmd_apply() {
  local base src name dst bak mark
  base="$(engine_base)"
  [[ "$base" == "$REQUIRED_BASE" ]] || die "Cyder engine 的 CrossOver 基底是 ${base}，修補 DLL 是針對 ${REQUIRED_BASE} 建置的，不套用。請回報 issue。"
  verify_sources
  cmd_check >/dev/null && {
    cmd_check
    return 0
  }
  require_wine_stopped "套用 DLL 修補"
  for src in "$SRC_DIR"/*.dll; do
    name="${src##*/}"
    dst="$DST_DIR/$name"
    bak="$dst.macmeow-orig"
    mark="$dst.macmeow-applied"
    [[ -f "$dst" ]] || die "找不到 ${dst}"
    if cmp -s "$src" "$dst"; then
      echo "${name}：已套用"
      continue
    fi
    # 目標檔若是本專案先前裝上去的（舊版修補），保留既有備份；否則它就是 engine 原檔，更新備份。
    if ! [[ -f "$bak" && -f "$mark" && "$(cat "$mark")" == "$(sha256 "$dst")" ]]; then
      cp -p "$dst" "$bak"
    fi
    cp "$src" "$dst"
    sha256 "$dst" >"$mark"
    echo "${name}：已套用（原檔備份 ${bak}）"
  done
}

cmd_restore() {
  local bak dst name mark
  for bak in "$DST_DIR"/*.dll.macmeow-orig; do
    [[ -f "$bak" ]] || {
      echo "DLL 修補：無備份"
      return 0
    }
    require_wine_stopped "還原 DLL"
    dst="${bak%.macmeow-orig}"
    name="${dst##*/}"
    mark="$dst.macmeow-applied"
    if [[ -f "$mark" && -f "$dst" && "$(cat "$mark")" == "$(sha256 "$dst")" ]]; then
      cp -p "$bak" "$dst"
      echo "${name}：已還原"
    else
      echo "${name}：目前不是本專案的修補版（engine 已更新？），只刪除過期備份"
    fi
    rm -f "$bak" "$mark"
  done
}

case "${1:-}" in
  check | apply | restore) "cmd_$1" ;;
  *) usage "check|apply|restore" ;;
esac
