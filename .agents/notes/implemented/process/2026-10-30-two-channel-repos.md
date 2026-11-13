# Agent Note: 用两个 dnf repo section 表达 nightly 与 stable

Status: implemented

## Problem

预发布包（`0.2.2~rc.2`）与正式包（`0.2.2`）要分开投递：想要预发布体验的用户能装到 rc，只想稳的用户不会被 rc 打中。应用侧还要能显示「切到哪个渠道」。

## Decision

发布 tag 由 `scripts/lib/release-channel.sh` 判定渠道——版本含预发布标记（`~`、`-rc`、alpha、beta 等）进 nightly，正式版进 stable 且同时进 nightly。`gh-pages` 上 `/stable` 与 `/nightly` 各有独立 repodata。随包的 `/etc/yum.repos.d/dsh-desktop.repo` 一份文件两个 section：stable `dsh-desktop`（enabled=1）、nightly `dsh-desktop-nightly`（enabled=0），手动 dnf 默认只走 stable。应用侧渠道只存上游 `settings-file` 的 `updates.channel`，默认 nightly。

## Alternatives considered

**两个 .repo 文件。** 用户要改渠道就得改文件归属，而 `.repo` 是 `%config(noreplace)` 的 rpm 配置，改文件会让升级覆盖提示变复杂。一份文件两个 section 只需切 `enabled`。

**应用自己在检查时拼 repo URL。** 等于绕过 dnf 的仓库配置，签名与元数据校验都要自己重做一遍，见 [更新交给 dnf](../architecture/2026-10-30-dnf-owns-updates.md)。

**用 dnf 的模块流或版本锁定表达渠道。** 语义过重，且 `--setopt` 与模块流的交互在 dnf5 下不易预测。

## Consequences

nightly 默认 disabled，所以应用内检查必须显式 `--enablerepo`/`--disablerepo`，否则看不到预发布。dnf 语义不降级：从 nightly 切回 stable 后，正式版追平前一直显示「已是最新」。迁移期根 `/repodata` 仍镜像 nightly 供老应用使用，收拢条件见 [PLAN.md](../../../../PLAN.md)。
