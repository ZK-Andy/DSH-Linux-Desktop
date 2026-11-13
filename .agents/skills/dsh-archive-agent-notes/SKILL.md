---
name: dsh-archive-agent-notes
description: 在把 Agent Note 归档（移进 .agents/notes/archived/）时使用，或在判断一份旧 note 该归档、该保留、还是该删除时使用。
---

# 归档 Agent Note

规则的家在 [`.agents/notes/README.md`](../../notes/README.md) 与 [`archived/AGENTS.md`](../../notes/archived/AGENTS.md)。本技能是执行一次归档的步骤。

## 先判断该不该归档

三个条件同时成立才归档：决定已经完结、理由不太会再指导未来工作、记录仍有历史价值。

- 全部不成立，且内容只是小 UI 调整或纯机械改动 → 直接删（三件一起删，修入向链接）。
- 决定还在生效、只是描述过时 → **不要归档**，就地改事实，见 [`implemented/AGENTS.md`](../../notes/implemented/AGENTS.md)。
- 是 `proposed/` 且过时 → reject，不归档。

## 执行

1. 移进 `archived/{class}/`，类目录沿用原 note 的类。
2. 保留 `Status: implemented`，在它下面紧接一行 `Archived: YYYY-MM-DD`。这是归档期间唯一允许的正文改动。
3. 修好或删掉所有指向它的入向链接。
4. 跑 `pnpm run verify-archived-agent-notes --write` 把内容哈希追加进 `manifest.json`。

`manifest.json` 只增不改。已封存条目一旦入库就冻结：不改、不重排、不翻译、不修复、不删除、不移动，指向外部的链接也不管。

## 常见错误

**归档了还在生效的决定。** 结果是现行树里没有权威，`archived/` 里有一份没人敢改的。判断标准是「未来的人会不会需要这条理由」，不是「这条是不是很老」。

**只移了主文件。** 这个仓库是中文单语，没有 `.zh.md` 与 `.i18n.yaml` 侧车，所以搬一个文件就够；但如果哪天加了侧车，三件必须一起搬。

**忘了 --write。** 门禁会以「manifest 里没有这个文件」失败。
