#!/bin/bash
# AGENTS.md 規範中 prek 內建 hook 檢查不了的部分（prek.toml 的 local hook 呼叫）。全部通過時不輸出，違規時印出原因並以 1 結束。
#
# 用法：bash tools/dev/lint.sh <檢查...>
#   gitignore       必須忽略的路徑（遊戲／登入器檔案、login.txt、.env、build/、debug/、dist/）仍被 .gitignore 忽略
#   justfile        每個 tools/*/*.sh（lib.sh 除外）與 experiments/build.sh 各有一個 recipe，recipe 只轉呼叫腳本
#   external-state  有 apply 的腳本也有 check、restore；能 restore 的腳本由 uninstall.sh 呼叫並列在 docs/external-state.md
#   dlls            patches/bin 與 SHA256SUMS 一致；patches/bin 有變更時 patches/SOURCES.md 也要更新
#   usage           參數錯誤一律經 usage／usage_doc 以 64 結束：以 $1 分派的 case 要有 *) usage 分支，不用 die、不直接 exit 64
#   release-files   CHANGELOG.md 有「## Unreleased」；VERSION 與已發佈的段落只能由 release.sh prepare 修改
#   app             App 以 build-app.sh 的參數編譯且沒有警告（含 app/make-*.swift）
set -euo pipefail
# shellcheck source=../lib.sh
source "$(cd "$(dirname "$0")/.." && pwd)/lib.sh"
cd "$ROOT"

bad=0
fail() {
  echo "$*" >&2
  bad=1
}

lint_gitignore() {
  local p
  for p in "${GAME_FILES[@]}" Data/Base.wz login.txt .env build/x debug/x dist/x; do
    git check-ignore -q --no-index "$p" || fail ".gitignore 必須忽略 ${p}"
  done
}

lint_justfile() {
  local line recipe="" doc=0 body=0 path p
  local paths=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_-]*)([[:space:]][^:]*)?:$ ]]; then
      recipe="${BASH_REMATCH[1]}"
      [[ "$recipe" == _* || "$doc" == 1 ]] || fail "justfile：recipe ${recipe} 缺少一行說明註解"
      body=0
    elif [[ "$line" == "    "* ]]; then
      [[ -n "$recipe" ]] || continue
      body=$((body + 1))
      ((body == 1)) || fail "justfile：recipe ${recipe} 只能有一行（轉呼叫腳本）"
      if [[ "$line" =~ ^\ {4}@bash\ ([^ ]+\.sh)\ \"\$@\"$ ]]; then
        path="${BASH_REMATCH[1]}"
        [[ -f "$path" ]] || fail "justfile：${recipe} 呼叫的 ${path} 不存在"
        paths+=("$path")
      elif [[ "$recipe" != _default ]]; then
        fail "justfile：${recipe} 只能是 @bash <腳本> \"\$@\""
      fi
    elif [[ -z "$line" ]]; then
      recipe=""
    fi
    # recipe 的說明註解可以與 recipe 之間隔著 [group(...)] 等屬性
    if [[ "$line" == "# "* ]]; then
      doc=1
    elif [[ "$line" != "["* ]]; then
      doc=0
    fi
  done <justfile
  for p in tools/*/*.sh experiments/build.sh; do
    [[ "$p" == tools/lib.sh ]] && continue
    case " ${paths[*]+${paths[*]}} " in
      *" $p "*) ;;
      *) fail "justfile：${p} 沒有對應的 recipe" ;;
    esac
  done
}

lint_external_state() {
  local f name
  for f in scripts/*.sh; do
    name="${f##*/}"
    if grep -q '^cmd_apply()' "$f"; then
      grep -q '^cmd_check()' "$f" && grep -q '^cmd_restore()' "$f" \
        || fail "${name}：有 cmd_apply 就要有 cmd_check 與 cmd_restore"
      grep -Fq 'usage "check|apply|restore"' "$f" || fail "${name}：子指令錯誤時要 usage \"check|apply|restore\""
    fi
    grep -Eq '^cmd_restore\(\)|lib/engine-patch\.sh' "$f" || continue
    grep -Fq "run_script $name restore" scripts/uninstall.sh || fail "${name}：scripts/uninstall.sh 沒有呼叫 run_script ${name} restore"
    grep -Fq "$name restore" docs/external-state.md || fail "${name}：docs/external-state.md 沒有列出 ${name} restore"
  done
}

lint_dlls() {
  (cd patches/bin/x86_64-windows && shasum -a 256 -c --quiet --strict ../SHA256SUMS) || fail "patches/bin/SHA256SUMS 與 DLL 不符"
  # 與 HEAD 比較：commit 時 prek 已把未暫存的變更收起來，所以就是這次 commit 的內容
  if git rev-parse -q --verify HEAD >/dev/null && [[ -n "$(git diff --name-only HEAD -- patches/bin)" ]]; then
    [[ -n "$(git diff --name-only HEAD -- patches/SOURCES.md)" ]] || fail "patches/bin 有變更，patches/SOURCES.md 也要更新（docs/wine-patches.md）"
  fi
}

# bad_dispatch <檔案>：印出缺少 *) usage 分支、以 $1 分派的 case（頂層，或分派到 cmd_*／patch_*）的行號。
# 巢狀 case 以相同縮排的 esac 配對。
bad_dispatch() {
  awk '
    !open && /^[[:space:]]*case "\$(1|\{1[^}]*\})" in/ {
      open = 1; line = NR; ind = $0; sub(/case.*/, "", ind); top = (ind == ""); disp = 0; ok = 0; next
    }
    open && /(cmd|patch)_/ { disp = 1 }
    open && /^[[:space:]]*\*\)[[:space:]]+usage(_doc)?([[:space:];]|$)/ { ok = 1 }
    open && $0 ~ "^" ind "esac" {
      if ((top || disp) && !ok) print line
      open = 0
    }' "$1"
}

# 錯誤的參數一律經 usage（common.sh）或 usage_doc（tools/lib.sh）以 64（EX_USAGE）結束
lint_usage() {
  local f line
  for f in scripts/*.sh scripts/lib/*.sh tools/*/*.sh; do
    if grep -q '^cmd_[a-z_]*()' "$f" && ! grep -Eq '^[[:space:]]*\*\)[[:space:]]+usage(_doc)?([[:space:];]|$)' "$f"; then
      fail "${f}：分派子指令的 case 要以 *) usage 或 *) usage_doc 結尾"
    fi
    for line in $(bad_dispatch "$f"); do
      fail "${f}:${line}：以 \$1 分派的 case 要有 *) usage 或 *) usage_doc 分支"
    done
    if grep -Eq '^[^#]*die "[^"]*(用法|未知)' "$f"; then
      fail "${f}：參數錯誤要用 usage 或 usage_doc（以 64 結束），不要用 die"
    fi
    [[ "$f" == scripts/lib/common.sh ]] && continue
    if grep -Eq '^[^#]*exit[[:space:]]+64([^0-9]|$)' "$f"; then
      fail "${f}：以 64 結束要經由 usage 或 usage_doc"
    fi
  done
}

# released：CHANGELOG 從第一個已發佈版本的標題開始的內容
released() { awk 'f || (/^## / && $0 != "## Unreleased") { f = 1; print }'; }

lint_release_files() {
  grep -qx '## Unreleased' CHANGELOG.md || fail "CHANGELOG.md 缺少「## Unreleased」標題"
  # tools/release/release.sh prepare 以 MACMEOW_RELEASE=1 commit
  [[ "${MACMEOW_RELEASE:-}" == 1 ]] && return
  git rev-parse -q --verify HEAD >/dev/null || return 0
  [[ "$(cat VERSION)" == "$(git show HEAD:VERSION)" ]] || fail "VERSION 只能由 tools/release/release.sh prepare 修改"
  [[ "$(released <CHANGELOG.md)" == "$(git show HEAD:CHANGELOG.md | released)" ]] \
    || fail "CHANGELOG.md 已發佈的版本不能修改；新條目寫在「## Unreleased」下"
}

lint_app() {
  local sdk f
  mkdir -p build/check
  compile_app build/check/MacMeow -warnings-as-errors || fail "app/Sources 編譯失敗或有警告"
  sdk="$(xcrun --sdk macosx --show-sdk-path)"
  for f in app/make-*.swift; do
    swiftc -typecheck -warnings-as-errors -sdk "$sdk" "$f" || fail "${f} 編譯失敗或有警告"
  done
}

(($# > 0)) || usage_doc
for check in "$@"; do
  case "$check" in
    gitignore | justfile | external-state | dlls | usage | release-files | app) "lint_${check//-/_}" ;;
    *) usage_doc ;;
  esac
done
exit "$bad"
