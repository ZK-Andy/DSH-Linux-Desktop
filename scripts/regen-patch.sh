#!/usr/bin/env bash
# 生成或重生成 patches/ 下的补丁，同时保留补丁首行的说明（preamble）。
#
#   scripts/regen-patch.sh <补丁名> <base> <head> [--repo <上游克隆>] [--reason "为什么"]
#                          [--exception "规则 N：…"] -- <路径>...
#
# 补丁名可以是 `0026-desktop-linux-frameless` 或 `patches/0026-desktop-linux-frameless.patch`。
# base/head 与路径都属于上游克隆（默认 ./upstream，`git -C <repo> diff` 里解析）。
#
# 规则（PLAN.md §10 M8）：
# - 已存在的补丁：读出现有 preamble 原样保留，传 --reason/--exception 视为改理由，直接报错；
# - 不存在的补丁：必须给 --reason，写成首行 `变化理由：…`；--exception 的内容要以「规则 N」开头；
# - 两者都缺、或现有 preamble 没有 `变化理由：` 行，报错退出；
# - 正文只经本脚本写入 patches/，不要直接 `git diff > patches/…`。
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

usage() {
  sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
}

[[ $# -ge 3 ]] || usage

name=$1; base=$2; head=$3; shift 3
repo=upstream; reason=''; exception=''; paths=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) [[ $# -ge 2 ]] || usage; repo=$2; shift 2 ;;
    --reason) [[ $# -ge 2 ]] || usage; reason=$2; shift 2 ;;
    --exception) [[ $# -ge 2 ]] || usage; exception=$2; shift 2 ;;
    --) shift; paths=("$@"); break ;;
    *) usage ;;
  esac
done

[[ ${#paths[@]} -gt 0 ]] || { echo "regen-patch: 未给出路径" >&2; exit 2; }
[[ -d "$repo/.git" || -f "$repo/.git" ]] || { echo "regen-patch: $repo 不是 git 仓库" >&2; exit 2; }

[[ "$name" == patches/*.patch ]] || name="patches/${name%.patch}.patch"
[[ "$name" == patches/*.patch ]] || name="${name}.patch"

body=$(mktemp)
trap 'rm -f "$body"' EXIT
# core.abbrev=7：与现有补丁的 index 缩写一致，重生成结果可直接与旧正文逐字节比较。
git -C "$repo" -c core.abbrev=7 diff --no-ext-diff --no-color --binary "$base" "$head" -- "${paths[@]}" > "$body"
if [[ ! -s "$body" ]]; then
  echo "regen-patch: ${base}..${head} 在给定路径上没有差异，拒绝写出空补丁" >&2
  exit 1
fi

if [[ -f "$name" ]]; then
  [[ -z "$reason" ]] || { echo "regen-patch: 已存在的补丁不接受 --reason，改理由请直接改 $(basename "$name") 首行" >&2; exit 2; }
  [[ -z "$exception" ]] || { echo "regen-patch: 已存在的补丁不接受 --exception，请直接改 $(basename "$name") 的例外行" >&2; exit 2; }
  preamble=$(awk '/^diff --git /{exit} {print}' "$name")
  grep -q '^变化理由：' <<<"$preamble" || {
    echo "regen-patch: $(basename "$name") 的 preamble 缺「变化理由：」行，先补首行再重生成" >&2
    exit 1
  }
else
  [[ -n "$reason" ]] || { echo "regen-patch: 新补丁必须给 --reason" >&2; exit 2; }
  preamble="变化理由：${reason}"
  if [[ -n "$exception" ]]; then
    [[ "$exception" == 规则* ]] || { echo "regen-patch: --exception 要以「规则 N」开头（patch-surface.sh 只认规则 4）" >&2; exit 2; }
    preamble="${preamble}"$'\n'"例外：${exception}"
  fi
fi

{ printf '%s\n' "$preamble"; cat "$body"; } > "$name.tmp"
mv "$name.tmp" "$name"
echo "==> $(basename "$name") $(grep -c '^diff --git ' "$name") 个文件 / $(wc -l < "$name") 行"
