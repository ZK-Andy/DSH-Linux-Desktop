# Agent Note: 用静态断言守住补丁形状

Status: implemented

## Problem

`AGENTS.md` 的规则里有一条可枚举的硬指标（每个补丁在 `main.ts` 净增不超过 15 行）和几条结构性约定（一个补丁一个变化理由、除 `main.ts` 外一个上游文件只归一个补丁、豁免必须登记）。只写在文档里，重放补丁时没人会逐条核对。

## Decision

`scripts/patch-surface.sh` 只读 `patches/` 做静态断言，在 `apply-patches.sh` 之前运行：每个补丁首行为 `变化理由：`；单补丁 `main.ts` 净增超 15 行时必须有 `例外：规则 4`；同一上游文件被多个补丁触碰时，`PLAN.md` §10 登记的补丁集合必须与实际集合完全相等（数量不得上升）；补丁新增文件不得与 `apply-patches.sh` 的 `ASSETS` 表目标重合；§10 引用的补丁必须存在。豁免的登记处只有 `PLAN.md` §10，判定靠字符串命中，条目删除后检查自动变硬。

## Alternatives considered

**只靠评审。** 规则 4 是可枚举数字，人工数 15 行在多补丁叠加时极易出错，而且失败没有留痕。

**每次重建补丁让它们天然合规。** 补丁的历史来源（见 [补丁拼接](../architecture/2026-10-30-patch-sequence-from-reference-projects.md)）决定了它们的边界不是设计的产物，重建等于重做别人的试错。

**用统一的 lint 检查补丁文本。** patch 是带 context 的 diff，通用 lint 不认识 `main.ts` 净增这类语义。

## Consequences

规则有了执行体，但也带来维护负担：`PLAN.md` §10 成为唯一豁免源，写错格式检查就看不见。豁免条目完成即删除，删除后对应断言转为常规检查。
