#!/usr/bin/env bash
# 发布渠道的唯一事实来源：由 git tag 判定这版进 stable 还是 nightly。
#
# 约定（与 package.yml 解析 rpm Release 同源）：发布 tag 一律是 `v<上游版本>-<rpm Release>`，
# 例如 v0.2.2~rc.2-1、v0.2.2-1。去掉 `v` 与末尾 `-<Release>` 后，版本段里仍带 `-` 或 `~`
# 就是预发布 → nightly；否则是正式版 → stable（正式版同时也会进 nightly，见 release.yml）。
#
#   source scripts/lib/release-channel.sh
#   channel="$(release_channel_for_tag "$GITHUB_REF_NAME")"
set -euo pipefail

release_channel_for_tag() {
  local tag="${1:?缺少 tag，例如 v0.2.2-rc.2-1}"
  local version
  version="$(printf '%s' "${tag#v}" | sed -E 's/-[0-9]+$//')"
  case "$version" in
    *-* | *~*) printf 'nightly\n' ;;
    *) printf 'stable\n' ;;
  esac
}
