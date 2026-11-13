# Agent Note: 先走 Releases，dnf 仓库后置

Status: implemented

## Problem

交付需要两个通道：直接把 rpm 放到 GitHub Releases，和用 dnf 仓库做更新发现。前者不需要静态托管，后者要 `gh-pages`、repodata 生成与签名。

## Decision

先做 Releases（A），dnf 仓库（B）后置。A 阶段把 rpm、`SHA256SUMS.txt` 与公钥发到 Releases 即可闭环验收口径 R1–R5；B 追加时只加 `gh-pages` 上的 repodata 与 `.repo` 文件，不改包结构与安装布局。今天两者都已落地：Releases 仍提供 rpm 与公钥，dnf 仓库是更新发现与安装的唯一通道。

## Alternatives considered

**一开始就建 dnf 仓库。** 会把 repodata 生成、签名、`gh-pages` 同步三件事压在首个可用版本之前，而它们都不影响「装得上、能更新」的首次验证。

**只做 Releases，永远不做仓库。** 更新发现要靠应用自己去查 GitHub API，等于在应用里重建一份包索引，与「更新交给 dnf」的决定冲突。

## Consequences

迁移期多一份兼容负担：`gh-pages` 根 `/repodata` 镜像 nightly，供未升级到双渠道版的老应用继续检查；用户改过的旧 `.repo` 缺渠道 section 时，helper 与应用侧退回单仓库查询。收拢条件记在 [PLAN.md 的待迁移表](../../../../PLAN.md)。
