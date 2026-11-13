# Agent Note: 托盘与无边框窗口

Status: implemented

## Problem

官方客户端在 Linux 上没有托盘入口，关窗即退出，等着接活的用户无处可点。窗口边框在 Fedora GNOME 下与官方 macOS/Windows 的外观不一致。

## Decision

托盘由 `0005-tray` 提供：把上游 `DesktopTray` 的 `win32` 门放宽到 Linux，图标按平台选 `tray-linux.png`，菜单含显示窗口、退出、关于与检查更新，文案落在 `locale-linux.ts`。无边框窗口由 `0006-window-frameless` 提供：实现在新文件 `desktop-window.ts`、`linux-window.ts`、`linux-frame.ts`，Web 端窗口按钮同批改。窗口尺寸与最大化记忆落在 `0007-window-size-memory`，存为上游 `settings-file` 的 looseObject 根字段。

## Alternatives considered

**在渲染层做自绘窗口框架。** 渲染层改动会随上游前端重构失效，且拖拽区域与系统手势的匹配要在 Web 侧重做一遍。

**用系统标题栏，不做无边框。** 与官方 macOS/Windows 外观不一致，窗口按钮的位置与行为也不统一。

## Consequences

窗口层与托盘层各在独立新文件里，`main.ts` 只留挂钩，因此 `main.ts` 净增为负。托盘图标是二进制资产，由 `scripts/apply-patches.sh` 放到位，补丁里只放渲染脚本。
