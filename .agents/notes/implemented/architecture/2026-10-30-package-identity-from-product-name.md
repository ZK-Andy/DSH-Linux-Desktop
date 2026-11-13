# Agent Note: 包身份由 productName 派生，菜单名单独覆盖

Status: implemented

## Problem

electron-builder 用 `productName` 同时决定两件互斥的事：`/opt` 目录名（进而决定 `Exec` 路径）与桌面菜单里的显示名。显示名要写「DeepSeek Harness」，路径里不能有空格。

## Decision

`productName: "deepseek-harness-desktop"` 保持路径安全，`/opt/deepseek-harness-desktop` 由它派生；desktop 文件里的 `Name` 用 `linux.desktop.entry.Name` 单独覆盖成 `DeepSeek Harness`。`packageName: "dsh-desktop"` 是 rpm 的 `Name`，`executableName: "deepseek-harness"` 是可执行名，`desktopName: "dsh-desktop"` 配 `linux.syncDesktopName: true` 定桌面文件名。

## Alternatives considered

**`productName` 直接用带空格的显示名。** 路径里出现空格，`Exec` 要转义，`/opt` 目录名也不稳定；而且 electron-builder 后续所有 derived 路径都会带上它。

**afterPack 阶段改名。** 需要在打包后重写 `/opt` 目录与 desktop 文件，等于给 builder 的输出做二次加工，两处事实分裂。

## Consequences

每个身份只有一个来源，改显示名不动路径。`StartupWMClass` 仍由 Electron 版本决定，只能实测后钉死，见 [PLAN.md](../../../../PLAN.md)。
