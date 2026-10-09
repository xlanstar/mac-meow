#!/bin/bash
# commit-msg hook（prek.toml）：AGENTS.md 規定 commit 必須有 body（subject 之後空一行再寫內容）。
# fixup!/squash!/amend! 與 Merge/Revert 訊息不檢查；格式與長度交給 committed。
set -euo pipefail

msg_file="${1:?用法：$0 <commit-msg 檔案>}"
comment_char="$(git config --get core.commentChar 2>/dev/null || true)"
comment_char="${comment_char:-#}"

subject=""
line_no=0
has_body=0
while IFS= read -r line || [[ -n "$line" ]]; do
  # git commit -v 的 diff 從 scissors 行開始，之後都不是訊息內容
  [[ "$line" == "$comment_char ------------------------ >8 ------------------------" ]] && break
  [[ "$comment_char" != auto && "${line:0:1}" == "$comment_char" ]] && continue
  line_no=$((line_no + 1))
  if [[ $line_no -eq 1 ]]; then
    subject="$line"
  elif [[ $line_no -eq 2 && -n "$line" ]]; then
    echo "commit 訊息第 2 行必須是空行（subject 與 body 之間）" >&2
    exit 1
  elif [[ $line_no -gt 2 && "$line" =~ [^[:space:]] ]]; then
    has_body=1
    break
  fi
done <"$msg_file"

case "$subject" in
  fixup!* | squash!* | amend!* | Merge\ * | Revert\ *) exit 0 ;;
esac

if [[ $has_body -eq 0 ]]; then
  echo "commit 訊息缺少 body：subject 之後空一行，說明改了什麼與原因（AGENTS.md「Commits」）" >&2
  exit 1
fi
