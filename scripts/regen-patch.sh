#!/usr/bin/env bash
# 生成或重生成 patches/ 下的补丁，同时保留补丁首行的说明（preamble）。
#
#   scripts/regen-patch.sh <补丁名> <base> <head> [--reason "为什么"] [--exception "…"] -- <路径>...
#
# 补丁名可以是 `0026-desktop-linux-frameless` 或 `patches/0026-desktop-linux-frameless.patch`。
#
# 规则（PLAN.md §10 M8）：
# - 已存在的补丁：读出现有 preamble 原样保留，传 --reason 视为改理由，直接报错；
# - 不存在的补丁：必须给 --reason，写成首行 `变化理由：…`；
# - 两者都缺、或现有 preamble 没有 `变化理由：` 行，报错退出；
# - 正文由 `git diff <base> <head> -- <路径>...` 生成，只经本脚本写入 patches/。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

usage() {
  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

[[ $# -ge 3 ]] || usage

name=$1; base=$2; head=$3; shift 3
reason=''; exception=''; paths=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reason) [[ $# -ge 2 ]] || usage; reason=$2; shift 2 ;;
    --exception) [[ $# -ge 2 ]] || usage; exception=$2; shift 2 ;;
    --) shift; paths=("$@"); break ;;
    *) usage ;;
  esac
done

[[ ${#paths[@]} -gt 0 ]] || { echo "patch-surface: 未给出路径" >&2; exit 2; }

[[ "$name" == patches/*.patch ]] || name="patches/${name%.patch}.patch"
[[ "$name" == patches/*.patch ]] || name="${name}.patch"

body=$(mktemp)
trap 'rm -f "$body"' EXIT
git diff --no-ext-diff --no-color --binary "$base" "$head" -- "${paths[@]}" > "$body"
if [[ ! -s "$body" ]]; then
  echo "patch-surface: ${base}..${head} 在给定路径上没有差异，拒绝写出空补丁" >&2
  exit 1
fi

if [[ -f "$name" ]]; then
  [[ -z "$reason" ]] || { echo "已存在的补丁不接受 --reason，改理由请直接改 $(basename "$name") 首行" >&2; exit 2; }
  [[ -z "$exception" ]] || { echo "已存在的补丁不接受 --exception，请直接改 $(basename "$name") 的例外行" >&2; exit 2; }
  preamble=$(awk '/^diff --git /{exit} {print}' "$name")
  grep -q '^变化理由：' <<<"$preamble" || {
    echo "$(basename "$name") 的 preamble 缺「变化理由：」行，先补首行再重生成" >&2
    exit 1
  }
else
  [[ -n "$reason" ]] || { echo "新补丁必须给 --reason" >&2; exit 2; }
  preamble="变化理由：${reason}"
  [[ -z "$exception" ]] || preamble="${preamble}"$'\n'"例外：${exception}"
fi

{ printf '%s\n' "$preamble"; cat "$body"; } > "$name.tmp"
mv "$name.tmp" "$name"
echo "==> $(basename "$name") $(grep -c '^diff --git ' "$name") 个文件 / $(wc -l < "$name") 行"
