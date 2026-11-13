# Agent Note: 补丁按变化来源从参考项目拼接

Status: implemented

## Problem

Linux 桌面集成需要改构建链、打包配置、托盘、窗口、更新四个方向，上游只提供 macOS/Windows 的路径。每条都要真跑通才知道哪里会断。

## Decision

补丁按变化来源从已经真跑通过的参考项目拼接：流水线取 ffyfox/dsh-desktop-linux，office 与冒烟取 zhsj，rpm 硬化取 macOS-Terminal 的配方，包身份取 coderirse。每个补丁对应一个变化理由，编号 `0001`–`0009`、`0011`。

## Alternatives considered

**从零写整套 Linux 适配。** 等于把别人的试错重做一遍：electron-builder 在 Linux 上的目标解析、fpm 参数、`chrome-sandbox` 权限、rpmbuild 后处理，每一条都是踩过才知道的。

**只挑一个参考项目全盘照搬。** 每个项目只在自己那条路上跑通过；全盘照搬会把它的路线选择（比如换独立 Node）一并接受进来。

## Consequences

补丁的边界是历史拼接的结果，不是设计的产物：一个补丁里可能混着构建链与发布设置。收拢办法是 [AGENTS.md 的规则](../../../../AGENTS.md)与 `patch-surface.sh` 的静态断言，不是重新切分补丁。
