---
name: agent-experience
description: 在为用户或另一个代理设计交互时使用——工具的输出、失败提示、门禁的报错、文档的导航。也可用于评审既有输出「一个不知情的代理能不能用」。
---

# 代理体验

读者不一定是人。一个没有上下文的代理会读你写的报错、跑你写的门禁、按你写的文档行动。它的失败模式与人不同：它不会「感觉不对」，它只会照字面执行然后卡住。

## 报错要能直接照做

好的报错包含：什么坏了、在哪、下一步做什么。对比：

- `budgeted file does not exist` — 代理会去建一个空文件。
- `budgeted file does not exist (renamed or deleted? update scripts/doc-budgets.manifest.json in the same change)` — 代理知道该改清单而不是建文件。

第二句多了两层信息：可能的原因、以及唯一正确的动作。

## 门禁要能空过

一个门禁在「没有对象可查」时应该通过并说明查了 0 个，不是报错也不是假装查过。`verify-skill-invocation-metadata` 在没有 `agents/openai.yaml` 时检查 0 对，这是对的——它查的是两者的一致性，不是两者的存在。

反过来，门禁不能因为语料意外变空而静默通过。`repo-files.ts` 对不支持的 glob 写法大声失败而不是返回空集，就是这个道理。

## 文档要有可执行的下一步

「详见 PLAN.md」不是导航，是传球。链接要指向具体的节，并说清在那里能找到什么。

## 幂等与可重入

代理会重跑命令。`--write` 类操作要么只追加，要么明确告知会重写什么。`verify-archived-agent-notes --write` 只追加哈希、不改已有条目，这是它敢让人跑两次的原因。

## 技能描述写「何时用」

技能目录里每个 `SKILL.md` 的 `description` 回答的是「什么时候该读我」，不是「我是什么」。前者让代理在对的时候找到它，后者只在已经找到之后才有用。
