# Agent Note: sharp 移出 Electron 进程

Status: implemented

## Problem

Electron 在 Linux 上把 sharp/libvips 加载进自己的进程会因 glib 断言失败直接 `abort()`。用户贴一张图或让模型读一张本地图片，整个应用退出；重启后回到同一会话仍复现。

## Decision

Host 留在 Electron node 模式，sharp 移进由打包内 `resources/runtime/primary-runtime/dependencies/node` 启动的子进程，Host 经 IPC 调用。worker 脚本 `resources/sharp-worker.cjs` 走 `extraResources`（asar 外），`sharp` 与 `@img/**` 进 `asarUnpack`，worker 用 `app.asar.unpacked/node_modules` 的绝对路径 `require`。补丁只改 `packages/attachment/attachment-local/src/sharp.ts` 里的 `requireSharp`——那是全部图片处理的唯一入口。

## Alternatives considered

**整体换独立 Node。** 能解决崩溃，但会把插件市场的握手故障引进来，见 [Host 运行时决定](2026-10-30-host-keeps-electron-node.md)。

**降级为不显示图片。** 把能力砍掉换取稳定，附件与 `read_image` 直接不可用。

**等上游修 electron#46323。** issue 至今 open，没有排期；等待期间用户贴图即崩。

## Consequences

子进程崩溃只让当次调用失败，Host 存活并返回明确错误。启动依赖注入：dev 模式没有 primary-runtime node，回退 `PATH`，worker 与模块目录必须由 `DSH_SHARP_WORKER`/`DSH_SHARP_MODULE_DIR` 给出，缺了直接报错而不静默退化。上游哪天修了 glib 冲突，这层隔离可以单独摘掉。
