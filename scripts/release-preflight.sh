#!/usr/bin/env bash
# 发布前总检位：资产矩阵、验签、校验和自洽。
# 任何一项不满足都以非零退出，发布作业就此终止（fail closed）。
set -euo pipefail

dir="${1:?用法: scripts/release-preflight.sh <dist 目录>}"
fail() { echo "::error::$*" >&2; exit 1; }

rpm_files=("$dir"/*.rpm)
[[ ${#rpm_files[@]} -eq 1 && -f "${rpm_files[0]}" ]] || fail "dist 里应当恰好有一个 rpm，实际：$(ls "$dir")"
rpm="${rpm_files[0]}"
for f in RPM-GPG-KEY-dsh-desktop SHA256SUMS.txt; do
  [[ -f "$dir/$f" ]] || fail "缺少发布资产 $f"
done

# 验签：把随包公钥导入临时 rpmdb，再校对同一个文件。
keydb="$(mktemp -d)"
trap 'rm -rf "$keydb"' EXIT
export LC_ALL=C   # rpm -Kv 的输出随语言变化，判定只认退出码，文本仅留痕
rpm --dbpath "$keydb" --import "$dir/RPM-GPG-KEY-dsh-desktop"
if ! rpm --dbpath "$keydb" -Kv "$rpm" > "$keydb/verify.txt" 2>&1; then
  cat "$keydb/verify.txt" >&2
  fail "rpm 验签失败（签名缺失或公钥不匹配）"
fi
cat "$keydb/verify.txt"
# 退出码 0 已覆盖 digest 与签名；再兜底确认输出里没有 NOKEY。
grep -q 'NOKEY' "$keydb/verify.txt" && { cat "$keydb/verify.txt" >&2; fail "rpm 签名无对应公钥（NOKEY）"; }

# 体积下限：防止空包/截断包混进 Release。
size=$(stat -c %s "$rpm")
(( size > 100000000 )) || fail "rpm 体积异常：$size 字节"


# tag 尾部的 Release 必须与包内 Release 一致：v0.2.2-alpha.2-2 ⇒ Release 2。
tag="${GITHUB_REF_NAME:-}"
if [[ -n "$tag" ]]; then
  want_release=$(printf '%s' "$tag" | sed -n 's/^v.*-\([0-9][0-9]*\)$/\1/p')
  got_release=$(rpm -qp --qf '%{RELEASE}' "$rpm")
  [[ -n "$want_release" ]] || fail "tag 结尾缺少 Release 段：$tag"
  [[ "$want_release" == "$got_release" ]] || fail "tag 的 Release（$want_release）与包内 Release（$got_release）不一致"
fi

# 校验和文件必须只因自指而省略自身，且逐条复核通过。
(cd "$dir" && sha256sum -c SHA256SUMS.txt >/dev/null) || fail "SHA256SUMS.txt 复核失败"
echo "preflight OK: $(basename "$rpm")（$(numfmt --to=iec "$size")，Release $(rpm -qp --qf '%{RELEASE}' "$rpm")）"
