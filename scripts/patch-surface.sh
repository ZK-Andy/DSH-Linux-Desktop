#!/usr/bin/env bash
# 静态检查 patches/：补丁首行说明、上游文件归属、main.ts 净增、资源副本、PLAN §10 引用一致性。
# 在重放补丁之前运行，未登记的违规以非 0 退出。
#
# PLAN.md §10「待迁移」是唯一登记处：脚本把违规的定位串（文件路径、补丁编号、资源名）
# 在 §10 正文里做字面查找，命中即视为已登记，打印后放行；未命中即违规。
# §10 条目删掉后，对应检查自动变成硬失败。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

shopt -s nullglob
patches=(patches/*.patch)
[[ ${#patches[@]} -gt 0 ]] || { echo "patch-surface: patches/ 为空" >&2; exit 1; }

PLAN_MIGRATION=$(awk '/^## 10\./{inside=1; next} /^## 11\./{inside=0} inside' PLAN.md)
[[ -n "$PLAN_MIGRATION" ]] || { echo "patch-surface: PLAN.md 找不到「## 10. 待迁移」" >&2; exit 1; }

fail=0
violation() { printf '!! 违规：%s\n' "$*"; fail=1; }
registered() { printf '== 已登记（PLAN §10）：%s\n' "$*"; }
allow_or_fail() { # <说明> <登记串...>：任一登记串在 §10 出现即视为已登记
  local message=$1; shift
  local marker
  for marker in "$@"; do
    if grep -qF -- "$marker" <<<"$PLAN_MIGRATION"; then registered "$message"; return; fi
  done
  violation "$message"
}

# 1. 补丁首行说明
for patch in "${patches[@]}"; do
  if ! head -n 1 "$patch" | grep -q '^变化理由：'; then
    allow_or_fail "$(basename "$patch") 首行不是「变化理由：…」" '没有补丁首行写' 
  fi
done

# 2. main.ts 净增 ≤15，或有「例外：规则 4」
while IFS=$'\t' read -r patch net; do
  [[ "$net" -le 15 ]] && continue
  if awk '/^diff --git /{exit} {print}' "$patch" | grep -q '^例外：规则 4'; then
    continue
  fi
  allow_or_fail "$(basename "$patch") 的 main.ts 净增 ${net} 行，超过 15 且没有「例外：规则 4」行" "$(basename "$patch")" "$(basename "$patch" | cut -c1-4)"
done < <(python3 - "${patches[@]}" <<'PY'
import re, sys
for path in sys.argv[1:]:
    current = None
    added = removed = 0
    for line in open(path, encoding='utf-8', errors='replace'):
        if line.startswith('diff --git '):
            current = line.split(' b/', 1)[1].strip() if ' b/' in line else None
            continue
        if current != 'apps/desktop/src/main.ts':
            continue
        if line.startswith('+++') or line.startswith('---'):
            continue
        if line.startswith('+'):
            added += 1
        elif line.startswith('-'):
            removed += 1
    print(f"{path}\t{added - removed}")
PY
)

# 3. 除 main.ts 外，每个上游文件的补丁数 = 1（本模块新文件不受此限）
python3 - "${patches[@]}" <<'PY' > "$ROOT/.patch-surface-files"
import sys
for path in sys.argv[1:]:
    for line in open(path, encoding='utf-8', errors='replace'):
        if line.startswith('diff --git '):
            parts = line.rstrip('\n').split(' ')
            target = parts[-1][2:] if parts[-1].startswith('b/') else parts[-1]
            print(f"{path}\t{target}")
PY
while IFS=$'\t' read -r target patch_list; do
  count=$(tr ' ' '\n' <<<"$patch_list" | grep -c .)
  [[ "$count" -le 1 ]] && continue
  case "$target" in
    */node_modules/*|apps/desktop/src/main.ts) continue ;;
  esac
  allow_or_fail "$target 被 ${count} 个补丁触碰：$(tr ' ' '\n' <<<"$patch_list" | xargs -n1 basename | tr '\n' ' ')" "$target" "$(basename "$target")"
done < <(python3 - <<'PY'
import collections
touched = collections.defaultdict(list)
for line in open('.patch-surface-files', encoding='utf-8'):
    patch, target = line.rstrip('\n').split('\t')
    touched[target].append(patch)
for target, patch_list in sorted(touched.items()):
    if len(patch_list) > 1:
        print(f"{target}\t{' '.join(patch_list)}")
PY
)
rm -f "$ROOT/.patch-surface-files"

# 4. 补丁新增文件不与 apply-patches.sh 的 ASSETS 目标重合
assets=$(sed -n '/^ASSETS=(/,/^)/p' scripts/apply-patches.sh | grep -oE "^  '[^']+'" | sed "s/^  '//; s/'\$//")
while IFS= read -r entry; do
  [[ -n "$entry" ]] || continue
  src=${entry%%:*}
  dest=${entry#*:}; dest=${dest%%:*}
  [[ "$dest" == apps/* ]] || continue
  for patch in "${patches[@]}"; do
    if grep -qxF "+++ b/$dest" "$patch"; then
      allow_or_fail "$(basename "$patch") 内嵌了 $dest，该文件由 apply-patches.sh 从 $src 放置" "$(basename "$patch")" "$(basename "$dest")" "$src"
    fi
  done
done <<<"$assets"

# 5. PLAN §10 引用的补丁必须存在
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  if ! compgen -G "patches/${id}-*.patch" > /dev/null; then
    violation "PLAN §10 引用的补丁 ${id} 不存在"
  fi
done < <(grep -oE '`00[0-9]{2}`' <<<"$PLAN_MIGRATION" | tr -d '`' | sort -u)

if [[ $fail -ne 0 ]]; then
  echo "patch-surface: 存在未登记的违规，见上" >&2
  exit 1
fi
echo "patch-surface: ${#patches[@]} 个补丁通过（未登记违规 0）"
