# Agent Note: 项目名不含产物格式，仓库名与包名分离

Status: implemented

## Problem

命名要同时回答三个问题：这个项目叫什么、GitHub 仓库叫什么、rpm 的 `Name` 叫什么。混用会把产物格式写进身份，而产物格式会变。

## Decision

仓库是 `DSH-Linux-Desktop`（大小写一致，不缩写），rpm 的 `Name` 是 `dsh-desktop`，可执行名是 `deepseek-harness`，`/opt` 目录是 `deepseek-harness-desktop`。项目名里不出现 rpm 这个词，包格式是产物而不是身份。可执行名与上游 CLI 分开，避免同名。

## Alternatives considered

**项目名带 rpm（如 `dsh-desktop-rpm`）。** 今天只出 rpm，明天若出别的格式，名字就成了错误的承诺；而改名要连带改仓库名与所有文档链接。

**包名与可执行名都用 `deepseek-harness`。** 与上游 CLI 同名，装到同一台机器上会冲突。

## Consequences

四个名字各有唯一来源，见 [PLAN.md 的命名一节](../../../../PLAN.md)。代价是新人要记两套名字：包叫 `dsh-desktop`，命令叫 `deepseek-harness`。
