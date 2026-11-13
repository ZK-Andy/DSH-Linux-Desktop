# Agent Note: 更新交给 dnf，应用只做发现与提示

Status: implemented

## Problem

应用需要更新机制。自更新要下载安装包、校验、然后替换 `/opt` 下的文件——这些文件由 rpm 拥有，绕过包管理器写入会让 rpmdb 与磁盘不一致，之后 `dnf upgrade` 会踩到被改过的文件。

## Decision

唯一真源是包管理器。应用只负责发现可用版本（`dnf5 repoquery --upgrades`）、提示、经 `pkexec /usr/libexec/dsh-update-helper` 执行一条 `dnf5 upgrade`。应用不下载、不校验、不落盘安装包，不改写 `/opt` 与 `/usr`。

## Alternatives considered

**内置 electron-updater 自更新。** 上游自带这条路径，但它下载后直接替换安装目录，破坏 rpm 的所有权；与 dnf 并存时「谁在装」也不可判定。

**应用下载 rpm 再交给 dnf 装。** 多一份下载缓存与完整性校验要维护，而 dnf 从仓库取到的本来就是同一份文件。

## Consequences

更新能力的上限由 dnf 决定：语义上不降级，渠道只能靠 repo 的 enable/disable 表达。代价是要维护 `gh-pages` 上的 repodata 与签名链；发布布局与退出码见 [PLAN.md](../../../../PLAN.md)。
