# Agent Note: 出包与发版全在 CI，本地只跑 dev

Status: implemented

## Problem

rpm 构建、签名、发版需要 Fedora 环境、GPG 私钥与稳定的工具链。放在开发者机器上，产物不可复现，日志留在本地无法追溯，谁签的名也无从查证。

## Decision

GitHub Actions 是唯一出包处：`ubuntu-24.04` 装 `rpm xz-utils cpio` 后跑 electron-builder，签名、静态验收、容器冒烟、发 Release、刷新 repodata 都在同一条流水线里。本地只用 `scripts/dev-desktop.sh` 调补丁行为，不出包。

## Alternatives considered

**本地出包，手工上传。** 省掉 CI 的 90 分钟排队，但产物与签名不可追溯，且每台机器的 rpmbuild 版本不同会让 Release 号语义漂移。

**自建常开构建机。** 不依赖 GitHub 的额度，但要维护一台机器的工具链、密钥与可用性，故障时没人接管。

## Consequences

补丁迭代要等 CI 排队，所以本地保留了 `--check` 试打与 dev 启动两条快路。CI 坏掉等于当天不能发版；为此 `patch-gate.yml` 在 PR 阶段就把补丁与上游测试跑一遍，不把问题留给打包作业。
