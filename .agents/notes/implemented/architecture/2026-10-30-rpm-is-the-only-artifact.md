# Agent Note: 只出 rpm，不出 AppImage 与 deb

Status: implemented

## Problem

electron-builder 默认能出 AppImage、deb、rpm、tar.gz 四种 Linux 产物。产物越多，验收矩阵越大，而这个项目只服务 Fedora x86_64。

## Decision

`linux.target` 只有 `rpm`。不出 AppImage、deb、zip 或 tar.gz；`artifactName` 定为 `dsh-desktop-${version}-${arch}.${ext}`，与验收口径 R1 的 `dsh-desktop-*.rpm` 对齐。

## Alternatives considered

**同时出 AppImage。** AppImage 自带一套自更新路径（AppImageUpdate），与「更新只经 dnf」相悖；要么关掉它的自更新（那它就只是一层多余的启动器），要么并存两套更新语义。

**同时出 deb。** 这个项目不维护 Debian 系的打包与依赖名，出一份没人验收的产物只是把维护面摊薄。

## Consequences

分发只有一条通道，验收只有一种形状：静态看包、容器真装真启动、GNOME 真机看托盘。换发行版时只换 `linux.target` 与更新适配器，不需要重做产物矩阵。
