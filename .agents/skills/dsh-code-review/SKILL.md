---
name: dsh-code-review
description: 在评审本仓库的改动（PR、补丁重生成、脚本修改）时使用，或在自己提交前做一次自查时使用。
---

# 代码评审

**这是判据，不是清单。** 先跑 `pnpm run change-scope` 看这次动了哪些文件，再读 diff。

## 权威文档

改动是否合规由这些文件定义，不由直觉定义：[`AGENTS.md`](../../../AGENTS.md)（规则）、[`docs/architecture.md`](../../../docs/architecture.md)（形状）、[`PLAN.md`](../../../PLAN.md)（规格）、[`docs/AGENTS.md`](../../../docs/AGENTS.md)（文档标准）。

## 阻塞项

**补丁的首行与归属。** 每个补丁首行是 `变化理由：…`；除 `main.ts` 外一个上游文件只归一个补丁。`bash scripts/patch-surface.sh` 会替你查，但它查不出「理由写的是托词」——那要人看。

**`main.ts` 净增。** 超过 15 行必须有 `例外：规则 4，<原因>；待迁移：<条目>`，且原因要说明为什么这段只能在这里。看到例外就问：真的搬不走吗？

**实现 vs 挂钩。** 上游已有文件只该出现 import、一处调用、一处对象展开、类型扩展。出现成段的逻辑就是走错了地方。

**同一个事实有没有第二份。** 二进制放 `assets/`、`packaging/`，由 `apply-patches.sh` 放置；Release 号只来自 CI 环境变量；命名以 PLAN.md 为准。补丁里出现这些内容的副本就是重复。

**文档有没有变胖。** 新内容进了错的层级会让 `docs/` 变成杂物间；`pnpm run check:all` 只能查字数，查不出「这段其实属于 architecture.md」。

## 人工检查

改动碰了更新链时，问一遍渠道语义：nightly 默认 disabled，从 nightly 切回 stable 后正式版追平前会显示「已是最新」，这是预期的吗？

改动碰了打包时，问一遍产物：文件归谁所有、`%post` 是否幂等、`/etc` 与 `/usr` 有没有被应用写。

改动碰了文档时，问一遍读者：不知道上下文的人读完这段，能否知道该做什么。不能就说明它缺的是前提，不是细节。
