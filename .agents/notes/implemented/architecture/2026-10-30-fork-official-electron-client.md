# Agent Note: fork 官方 Electron 客户端，不自建桌面壳

Status: implemented

## Problem

Linux 上要交付一个能用的 DSH 桌面客户端。上一代交付物 `dotnet-deepseek-harness-desktop` 用 .NET 壳承载 Web 界面：渲染细节、输入法、快捷键、托盘行为都与官方客户端不一致，上游前端每改一次，壳里就要追一遍。

## Decision

从 `deepseek-ai/deepseek-harness`（MIT）fork，固定上游 tag，只叠加 Linux 需要的托盘与桌面集成补丁。UI、Chromium 渲染、Host 运行时全部来自官方 Electron 应用；本仓库交付 Fedora x86_64 的 rpm。

## Alternatives considered

**继续维护 .NET 壳。** 壳只能承载网页，原生菜单、托盘、拖放、快捷键的差异要逐个补，而且每轮上游前端改动都得重新对齐；差距只会越拉越大。

**从零写一个 Electron 应用。** 等于把上游已有的窗口、更新、设置、IPC 全部重写一遍，维护成本随上游每个版本线性增长。

## Consequences

维护成本集中在补丁重放：上游 tag 一变，十个补丁要重新生成、过门禁、跑冒烟。换来的是 UI 与官方逐像素一致，官方新增能力不需要移植就直接可用。
