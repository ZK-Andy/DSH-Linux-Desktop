#!/usr/bin/env bash
# 由已签名的 rpm 生成 Release 用的 version.json（更新链读取，见 README「更新模型」）。
# 用法：scripts/make-version-json.sh dist/dsh-desktop-*.rpm > dist/version.json
set -euo pipefail

rpm_file="${1:?用法: scripts/make-version-json.sh <rpm>}"
[[ -f "$rpm_file" ]] || { echo "找不到 $rpm_file" >&2; exit 1; }

rpm_version="$(rpm -qp --qf '%{VERSION}' "$rpm_file")"
rpm_release="$(rpm -qp --qf '%{RELEASE}' "$rpm_file")"
sha256="$(sha256sum "$rpm_file" | cut -d' ' -f1)"
size="$(stat -c %s "$rpm_file")"
name="$(basename "$rpm_file")"
# dnf 看到的完整版本是 Version 与 Release 两段；给更新链一个可直接比对的字符串。
human_version="${rpm_version//\~/-}-${rpm_release}"

printf '{\n'
printf '  "version": "%s",\n' "$human_version"
printf '  "rpmVersion": "%s",\n' "$rpm_version"
printf '  "rpmRelease": "%s",\n' "$rpm_release"
printf '  "package": "%s",\n' "$name"
printf '  "sha256": "%s",\n' "$sha256"
printf '  "bytes": %s,\n' "$size"
printf '  "publishedAt": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '  "signingKeyId": "428be141c85f90ee"\n'
printf '}\n'
