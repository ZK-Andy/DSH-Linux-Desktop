#!/usr/bin/env bash
# 由 git 历史生成 Release 正文：安装方式、签名信息、本版变更、资产清单、已知限制。
# 用法：scripts/release-notes.sh [上一个 tag] <当前 tag>
set -euo pipefail

prev="${1:-}"
current="${2:?用法: scripts/release-notes.sh [上一个 tag] <当前 tag>}"

printf '# DSH Linux Desktop %s\n\n' "$current"
printf '基于上游 DSH 桌面客户端的 Linux 无边框封装：RPM 包，x86_64，dnf5 系发行版。\n\n'

printf '## 安装 / Install\n\n'
printf '```bash\nsudo rpm --import ./RPM-GPG-KEY-dsh-desktop\nsudo dnf5 install ./dsh-desktop-*.rpm\n```\n\n'
printf '已装旧版升级：同样执行上面两条（公钥只需导入一次）。\n\n'

printf '## 签名 / Signature\n\n'
printf 'RPM 由仓库密钥签名：`RSA-4096`，Key ID `428be141c85f90ee`，\n'
printf '指纹 `782922FBB063DB2F51B3D33D428BE141C85F90EE`。公钥随本 Release 提供，\n'
printf '`version.json` 里的 `sha256` 与 `SHA256SUMS.txt` 可用于二次核对。\n\n'

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
printf -- '- `version.json` —— 更新链读取的版本元数据（版本、包名、sha256、大小）\n'
printf -- '- `SHA256SUMS.txt` —— 全部资产的校验和\n\n'

printf '## 已知限制 / Known limitations\n\n'
printf -- '- 仅 x86_64；依赖 dnf5（Fedora 41+ 等）。\n'
printf -- '- 托盘图标暂不跟随系统主题。\n'
printf -- '- 应用内更新链尚未实现：升级请重新下载本页 rpm 后 `sudo dnf5 install ./dsh-desktop-*.rpm`。\n'
printf -- '- GNOME 默认不显示托盘，需要 `gnome-shell-extension-appindicator`。\n'
