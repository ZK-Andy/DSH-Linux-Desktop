#!/usr/bin/env bash
# 由 git 历史生成 Release 正文：安装方式、签名信息、本版变更、资产清单、已知限制。
# 用法：scripts/release-notes.sh [上一个 tag] <当前 tag>
set -euo pipefail

prev="${1:-}"
current="${2:?用法: scripts/release-notes.sh [上一个 tag] <当前 tag>}"
# 渠道由 tag 判定（与 release.yml / publish-repo.sh 同一份规则），正文里据此写更新通道。
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/release-channel.sh"
channel="$(release_channel_for_tag "$current")"

printf '# DSH Linux Desktop %s\n\n' "$current"
printf '基于上游 DSH 桌面客户端的 Linux 无边框封装：RPM 包，x86_64，dnf5 系发行版。\n\n'

printf '## 安装 / Install\n\n'
printf '```bash\nsudo rpm --import ./RPM-GPG-KEY-dsh-desktop\nsudo dnf5 install ./dsh-desktop-*.rpm\n```\n\n'
printf '已装旧版升级：同样执行上面两条（公钥只需导入一次）。\n\n'

printf '## 更新渠道 / Channel\n\n'
if [[ "$channel" == stable ]]; then
  printf '本版是正式版：同时进入 `stable` 与 `nightly` 两个渠道。\n'
  printf '默认渠道是 `nightly`；想只收正式版，在应用内把渠道切到 `stable`。\n\n'
else
  printf '本版是预发布版：只进入 `nightly` 渠道，`stable` 不会收到它。\n'
  printf '默认渠道是 `nightly`；保持或切到 `nightly` 才会收到这类版本。\n\n'
fi
printf '切换渠道只决定升级时查哪个 dnf 仓库（`dsh-desktop` / `dsh-desktop-nightly`），\n'
printf '不改变安装方式：升级仍只经 dnf，且不降级；手动 `sudo dnf5 upgrade dsh-desktop` 走 stable。\n\n'

printf '## 签名 / Signature\n\n'
printf 'RPM 由仓库密钥签名：`RSA-4096`，Key ID `428be141c85f90ee`，\n'
printf '指纹 `782922FBB063DB2F51B3D33D428BE141C85F90EE`。公钥随本 Release 提供，\n'
printf '`SHA256SUMS.txt` 可用于二次核对。\n\n'

printf '## 本版变更 / Changes\n\n'
if [[ -n "$prev" ]]; then
  git log --no-merges --pretty='- %s (`%h`)' "$prev..$current" | sed '/^- $/d'
  printf '\n完整差异：https://github.com/%s/compare/%s...%s\n\n' "${GITHUB_REPOSITORY:-ZK-Andy/DSH-Linux-Desktop}" "$prev" "$current"
else
  printf '%s\n\n' '- 首个可生成正文的 tag；此前无历史。'
fi

printf '## 资产 / Assets\n\n'
printf -- '- `dsh-desktop-*.rpm` —— 已签名安装包（x86_64）\n'
printf -- '- `RPM-GPG-KEY-dsh-desktop` —— 发布公钥\n'

printf -- '- `SHA256SUMS.txt` —— 全部资产的校验和\n\n'

printf '## 已知限制 / Known limitations\n\n'
printf -- '- 仅 x86_64；依赖 dnf5（Fedora 41+ 等）。\n'
printf -- '- 托盘图标暂不跟随系统主题。\n'
printf -- '- 更新只经 dnf5 仓库（含 polkit helper）；非 dnf 系系统无法使用应用内检查与安装。\n'
printf -- '- GNOME 默认不显示托盘，需要 `gnome-shell-extension-appindicator`。\n'
