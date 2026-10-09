# shellcheck shell=bash
# Cyder engine 執行檔的位元組修補（patch-cyder-loopback.sh、patch-cyder-winemac.sh 共用）。在 common.sh 之後 source。
#
# 使用的腳本先設定：
#   PATCH_FILE   要修補的 engine 檔案；原檔備份為 <檔案>.macmeow-orig
#   PATCH_LABEL  訊息中的名稱
# 並定義：
#   patch_state  輸出 patched|unpatched|unknown（只在 PATCH_FILE 存在時呼叫）
#   patch_write  寫入修補位元組（apply 時呼叫；之後重新 ad-hoc 簽章並驗證）
# 然後呼叫 patch_main "$@"（check|apply|restore）。

PATCH_BAK="$PATCH_FILE.macmeow-orig"

# 輸出 patched|unpatched|unknown|missing
patch_status() {
  if [[ -f "$PATCH_FILE" ]]; then patch_state; else echo missing; fi
}

patch_check() {
  local s
  s="$(patch_status)"
  case "$s" in
    patched) echo "${PATCH_LABEL}：已套用" ;;
    unpatched) echo "${PATCH_LABEL}：未套用" ;;
    unknown) echo "${PATCH_LABEL}：未知版本" ;;
    missing) echo "${PATCH_LABEL}：找不到 ${PATCH_FILE}" ;;
  esac
  [[ "$s" == patched ]]
}

# 套用；engine 不是已知版本時回傳 2，不修改。
patch_apply() {
  case "$(patch_status)" in
    patched)
      echo "${PATCH_LABEL}：已套用"
      return 0
      ;;
    missing) die "找不到 Cyder engine：${PATCH_FILE}（請先開一次 Cyder）" ;;
    unknown)
      echo "${PATCH_LABEL}：${PATCH_FILE##*/} 不是已知版本（Cyder engine 已更新？），不修改。" >&2
      exit 2
      ;;
  esac
  require_wine_stopped "套用${PATCH_LABEL}"
  cp -p "$PATCH_FILE" "$PATCH_BAK" # 目前檔案是未修補的原檔（含 engine 更新後的新版），一律更新備份
  patch_write
  /usr/bin/codesign --force --sign - --preserve-metadata=entitlements "$PATCH_FILE" 2>/dev/null \
    || /usr/bin/codesign --force --sign - "$PATCH_FILE"
  if [[ "$(patch_state)" != patched ]] || ! /usr/bin/codesign --verify "$PATCH_FILE" 2>/dev/null; then
    cp -p "$PATCH_BAK" "$PATCH_FILE"
    die "${PATCH_LABEL}：套用後驗證失敗，已還原。"
  fi
  echo "${PATCH_LABEL}：已套用（原檔備份 ${PATCH_BAK}）"
}

# 還原並刪除備份；目前檔案不是修補版（engine 已更新或已刪除）時只刪除過期備份。
patch_restore() {
  [[ -f "$PATCH_BAK" ]] || {
    echo "${PATCH_LABEL}：無備份"
    return 0
  }
  require_wine_stopped "還原${PATCH_LABEL}"
  if [[ "$(patch_status)" == patched ]]; then
    cp -p "$PATCH_BAK" "$PATCH_FILE"
    echo "${PATCH_LABEL}：已還原"
  else
    echo "${PATCH_LABEL}：目前不是修補版（engine 已更新？），只刪除過期備份"
  fi
  rm -f "$PATCH_BAK"
}

patch_main() {
  case "${1:-}" in
    check | apply | restore) "patch_$1" ;;
    *) usage "check|apply|restore" ;;
  esac
}
