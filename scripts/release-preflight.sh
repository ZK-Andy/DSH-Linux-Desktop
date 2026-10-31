#!/usr/bin/env bash
# 发布前总检位：资产矩阵、验签、version.json 与 rpm 事实一致、校验和自洽。
# 任何一项不满足都以非零退出，发布作业就此终止（fail closed）。
set -euo pipefail

dir="${1:?用法: scripts/release-preflight.sh <dist 目录>}"
fail() { echo "::error::$*" >&2; exit 1; }

rpm_files=("$dir"/*.rpm)
[[ ${#rpm_files[@]} -eq 1 && -f "${rpm_files[0]}" ]] || fail "dist 里应当恰好有一个 rpm，实际：$(ls "$dir")"
rpm="${rpm_files[0]}"
for f in RPM-GPG-KEY-dsh-desktop version.json SHA256SUMS.txt; do
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

# version.json 必须与 rpm 的字节和头部事实一致。
python3 - "$dir/version.json" "$rpm" <<'PY'
import json, subprocess, sys, hashlib, os

meta_path, rpm_path = sys.argv[1], sys.argv[2]
meta = json.load(open(meta_path, encoding='utf-8'))
q = lambda fmt: subprocess.check_output(['rpm', '-qp', '--qf', fmt, rpm_path], text=True).strip()

def need(cond, msg):
    if not cond:
        print(f'::error::{msg}', file=sys.stderr)
        sys.exit(1)

digest = hashlib.sha256(open(rpm_path, 'rb').read()).hexdigest()
need(meta['package'] == os.path.basename(rpm_path), f"version.json 的 package 与文件不符：{meta['package']}")
need(meta['sha256'] == digest, 'version.json 的 sha256 与 rpm 字节不符')
need(int(meta['bytes']) == os.path.getsize(rpm_path), 'version.json 的 bytes 与 rpm 大小不符')
need(meta['rpmVersion'] == q('%{VERSION}'), f"version.json 的 rpmVersion 与包不符：{meta['rpmVersion']}")
need(meta['rpmRelease'] == q('%{RELEASE}'), f"version.json 的 rpmRelease 与包不符：{meta['rpmRelease']}")
# 更新链比较用的 version 是点分形式，tag 是发布形式，两者必须由同一组头部字段拼出。
expected_version = q('%{VERSION}').replace('~', '-') + '.' + q('%{RELEASE}')
expected_tag = 'v' + q('%{VERSION}').replace('~', '-') + '-' + q('%{RELEASE}')
need(meta['version'] == expected_version, f"version.json 的 version 不是点分形式：{meta['version']} ≠ {expected_version}")
need(meta.get('tag') == expected_tag, f"version.json 的 tag 与包不符：{meta.get('tag')} ≠ {expected_tag}")
print('version.json ↔ rpm 一致：', meta['version'], digest[:16])
PY

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
