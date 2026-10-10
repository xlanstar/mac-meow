#!/bin/bash
# commit-msg hook（prek.toml）：AGENTS.md 規定 commit 必須有 body（subject 之後空一行再寫內容）。
# fixup!/squash!/amend! 與 Merge/Revert 訊息不檢查；格式與長度交給 committed。
#
# 用法：bash tools/dev/check-commit-body.sh <commit-msg 檔案>
set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"

[[ -n "${1:-}" ]] || usage "<commit-msg 檔案>"
msg_file="$1"
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
  if ((line_no == 1)); then
    subject="$line"
  elif ((line_no == 2)) && [[ -n "$line" ]]; then
    die "commit 訊息第 2 行必須是空行（subject 與 body 之間）"
  elif ((line_no > 2)) && [[ "$line" =~ [^[:space:]] ]]; then
    has_body=1
    break
  fi
done <"$msg_file"

case "$subject" in
  fixup!* | squash!* | amend!* | Merge\ * | Revert\ *) exit 0 ;;
esac

((has_body)) || die "commit 訊息缺少 body：subject 之後空一行，說明改了什麼與原因（AGENTS.md「Commits」）"
