# Agent Note: 更新入口改上游状态机，复用官方更新 UI

Status: implemented

## Problem

应用内要能检查更新、提示、授权、安装、重启。上游已有一整套更新 UI（`update-dialog`、`update-presentation`）与一个状态机 `update-coordinator.ts`，但状态机直接 `new autoUpdater` 并依赖 `app-update.yml`。

## Decision

改 `update-coordinator.ts` 的状态机：把 electron-updater 的下载与安装路径整体替换成 dnf 的检查与 helper 调用，保留渲染层的契约——对话框与设置页指示器照旧按状态渲染。不另做原生 dialog。

## Alternatives considered

**另写一套原生 dialog 更新入口。** 两套更新界面后期必然要合并，等于白做一遍；而且用户会在不同入口看到不同的状态语义。

**禁用 electron-updater 后另开一路（保留原状态机）。** 两套状态机并存，谁在管「正在检查」这类瞬时状态无法判定。

## Consequences

更新语义与上游 UI 绑定：状态机的状态集合改了，渲染层要同批改。`0009-update-ui` 因此同时动 `update-coordinator.ts`、`update-presentation.ts` 与设置页，并带对应测试。
