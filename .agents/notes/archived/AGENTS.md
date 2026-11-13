# 冻结归档

`archived/` 存放已封存的 Agent Note：决定已完结、理由不太会指导未来工作，但记录仍有历史价值。它是快照，不是现行行为的权威——现行决定一律在 [`implemented/`](../implemented/AGENTS.md) 里。

**永不编辑已封存件。** 不改、不重排、不翻译、不修复、不删除、不移动。文档门禁跳过本树，包括它指向外面的链接。

归档动作是整体搬迁：把 note 移进 `archived/{class}/`、保留 `Status: implemented`、在 status 行下紧接一行 `Archived: YYYY-MM-DD`、修好或删掉所有指向它的入向链接。这是归档期间唯一允许的正文改动。搬完跑 `pnpm run verify-archived-agent-notes --write` 把新件的内容哈希追加进 `manifest.json`。

[`manifest.json`](manifest.json) 只增不改：`{version: 1, files: {路径: "sha256:…"}}`。`verify-archived-agent-notes` 拒绝任何已封存条目的改动或缺失、未知的类目录、以及不在清单里的新件；`--write` 只追加，不重写已有条目。

类目录随封存件出现。Git 不追踪空目录，所以刚克隆时只含件的类目录存在、其余不存在，这是正常状态。
