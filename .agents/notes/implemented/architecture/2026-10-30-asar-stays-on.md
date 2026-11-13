# Agent Note: asar 保持开启

Status: implemented

## Problem

参考项目在 Linux 上关掉了 asar。开关本身只是一行配置，但它决定了应用启动后文件系统的形状：开启时 Node 侧看到的是 `app.asar` 虚拟包，关闭时看到的是普通目录。

## Decision

asar 保持开启，与官方 macOS/Windows 形态一致。需要真实路径的资源走 `extraResources`（asar 外）或 `asarUnpack`（`app.asar.unpacked`），不靠关 asar 换路径可见性。

## Alternatives considered

**关掉 asar。** 参考项目这么做是因为它把 Host 换成了独立 Node，需要直接 `require` 上游模块；本项目不换运行时，关 asar 只剩副作用——启动变慢、包内文件可被随意改写。

**整体开启但把整个 `node_modules` unpack。** 包体积翻倍，文件数暴涨，安装时间显著变长，只为绕过少数几个路径问题。

## Consequences

每个需要真实路径的资源都要显式声明归属：托盘 PNG 与 sharp worker 走 `extraResources`，sharp 与 `@img/**` 走 `asarUnpack`，见 [sharp 隔离](2026-10-30-sharp-out-of-process.md)。漏声明时表现为运行时找不到文件，而不是打包失败。
