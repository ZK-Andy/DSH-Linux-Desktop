# Agent Note: 静态验收与冒烟分工

Status: implemented

## Problem

参考项目的 Arch/PKGBUILD 断言与本项目的 rpm 无关，直接搬过来只会得到一堆恒真的检查。同时「包对不对」与「装了能不能起」是两类问题，混在一个脚本里失败原因不可分辨。

## Decision

`scripts/verify.sh` 只做 rpm 静态验收：包元数据、文件布局、desktop 入口、`Requires`、`%post`/`%postun` 内容，全部从 `rpm -qp` 一类只读查询得出。`scripts/smoke-install-rpm.sh` 起 `fedora:44` 容器真装真启动：`dnf5 install`、Xvfb 起会话、`xdotool` 确认窗口与 `WM_CLASS`、级联截图。两者在同一作业里先后跑，失败各自留痕。

## Alternatives considered

**一个脚本全查。** 静态失败与启动失败混在同一份输出里，且容器要起两遍或根本不必起。

**只做冒烟，不做静态。** 冒烟能证明能启动，证明不了文件归谁所有、`Requires` 是否齐、`%post` 是否幂等。

## Consequences

静态验收在秒级给出结论，冒烟要几分钟。冒烟截图只作人眼复核，崩溃或没建出窗口才判失败；CI 证明不了 GNOME 里的托盘可见性，那部分仍是真机人工验收。
