---
name: dsh-pre-push-checks
description: 在推送到远端前使用，或不确定该跑哪些检查时使用。
---

# 推送前检查

## 跑门禁

```sh
pnpm run check:all
```

七项文档门禁、两项补丁门禁、一项重复代码检查。它跑的就是 CI 的 `ci-static`，本地绿了 CI 不会因为同一批问题红。

## 补丁改动额外跑

```sh
bash scripts/patch-surface.sh
```

它查四件事：补丁首行是不是 `变化理由：…`、`main.ts` 净增是否超 15 行且没有例外、同一上游文件是否被多个补丁触碰（与 PLAN.md 待迁移一节登记不一致即失败）、以及补丁是否内嵌了 `apply-patches.sh` 已经负责放置的资源。

## 分支与提交

提交信息说清做了什么和为什么；不要一个提交里混两件无关的事。PR 目标分支是 `main`，`patch-gate.yml` 会打补丁并跑受影响的上游测试——本地不用启 CI 调试，那是慢的。

## 远端写操作先要许可

`git push`、触发或取消 CI、创建 Release、改仓库设置、删 artifact、发 issue 都是远端写操作，每次都需要用户事先许可。本地能验证的先在本地验证。
