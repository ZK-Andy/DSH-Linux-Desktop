# Agent Note: LibreOfficeKit 在 asar 下的引擎探测回退

Status: implemented

## Problem

Office 预览在 Linux 打包形态下找不到 LibreOfficeKit：引擎探测走的是文件系统路径，而打包后相关文件在 asar 里，普通 `stat` 看不见。

## Decision

`0004-libreoffice-engine` 给引擎探测加一条回退：asar 路径解析失败时改用 `app.asar.unpacked` 下的实际位置。只改探测，不改引擎调用约定。

## Alternatives considered

**关掉 asar。** 会让整包的文件布局偏离官方形态，也影响启动路径；为一次探测失败付这个代价不成比例。

**把 LibreOfficeKit 相关文件整体搬出 asar。** 需要枚举一整套运行时依赖，漏一个就在别的文档类型上再坏一次。

## Consequences

只修了探测这一环；引擎真正加载失败时仍然是明确错误。上游若改变 asar 内的布局约定，这条回退要跟着改。
