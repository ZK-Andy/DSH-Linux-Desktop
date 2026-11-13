# Agent Note: 关闭到托盘与单实例复用上游实现

Status: implemented

## Problem

验收口径要求点关闭窗口后进程仍在、从托盘退出才结束，且只能跑一个实例。这两件事看起来都要写代码。

## Decision

两件都不写补丁。上游 `apps/desktop/src/main.ts` 已无条件 `preventDefault()` 后隐藏窗口，单实例由 `apps/desktop/src/single-instance.ts` 的 `claimDesktopSingleInstance` 提供。本项目只补托盘入口，见 [托盘与窗口补丁](../feature/2026-10-30-tray-and-frameless-window.md)。

## Alternatives considered

**自己实现关闭到托盘。** 与上游逻辑重复，两者会各自演进；上游哪天改了默认行为，我们的实现还要重新对齐。

**自己实现单实例锁。** 上游已经处理了锁文件、socket 与二次启动的转发，重写只会多一堆边界情况。

## Consequences

验收口径 R3 由上游行为满足，不是我们交付的。上游若改变这条默认行为，验收会失败而我们没有对应补丁——届时要先确认这是上游的有意变更还是缺陷。
