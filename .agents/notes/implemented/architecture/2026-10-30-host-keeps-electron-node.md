# Agent Note: Host 保持 Electron 自带的 Node

Status: implemented

## Problem

Linux 上有两个独立故障：Electron 进程内加载 sharp 会 abort（[electron#46323](https://github.com/electron/electron/issues/46323)），而把 Host 换成独立 Node 又会让插件市场卡死。参考项目 ffyfox/dsh-desktop-linux 选了后者，换来图片正常、市场坏。

## Decision

Host 由 Electron 以 node 模式托管（`ELECTRON_RUN_AS_NODE=1`），不替换成独立 Node；asar 保持开启，与官方形态一致。两个问题分头解决：图片走子进程隔离，见 [sharp 隔离](2026-10-30-sharp-out-of-process.md)。

## Alternatives considered

**换独立 Node，同时关 asar。** 参考项目走的路。它解决了图片崩溃，但市场热挂载的 409 卡死正是换运行时之后出现的握手失败；关 asar 又进一步偏离官方形态。

**只关 asar，不换 Node。** 关 asar 是独立 Node 路线的前提，不换 Node 时它只带来性能与安全上的退步，解决不了 glib 崩溃。

## Consequences

运行时形态与 macOS/Windows 官方客户端一致，插件市场在官方平台上验证过的行为在 Linux 上也成立。代价是图片必须走进程隔离，多一个 worker 与一组 `asarUnpack` 配置要维护。
