# 本地开发

本文讲怎么在这个仓库里改东西、怎么在本地验证。产品规格在 [PLAN.md](../PLAN.md)，架构在 [architecture.md](architecture.md)。

## 环境

需要 Node ≥ 24.9（门禁脚本用 Node 原生 TypeScript 剥离直接跑 `.ts`，不需要构建）、pnpm 11、git ≥ 2.26（`core.hooksPath` 要能按 worktree 设置）、`python3`（`patch-surface.sh` 用它解析补丁）、以及出包才用得到的 `rpm`、`xz-utils`、`cpio`。

首次克隆后跑一次 `pnpm install`。装依赖时 lefthook 的 postinstall 会把钩子装上；装不上或被拦时手动跑 `pnpm run hooks:install`。

## 日常三条命令

```sh
pnpm run check:all      # 全部门禁，提交前跑这个
pnpm run change-scope --base origin/main   # 相对 origin/main 改了哪些文件，给评审用
bash scripts/dev-desktop.sh   # 打补丁并起一个开发用客户端
```

`check:all` 并行跑三组：文档门禁（Markdown 折行、链接、字数预算、Agent Note 结构与格式、归档哈希、技能元数据）、补丁门禁（`patch-surface.sh`、shell 语法）、脚本门禁（`tsc --noEmit` 查类型、`oxlint` 查规范、`jscpd` 查重复）。CI 跑的是同一组，见 `pnpm run check:ci`。

## 改补丁

补丁由 `scripts/regen-patch.sh` 生成和重生成，不手写。流程是：改 `upstream/` 工作树里的文件，然后按补丁重生成；首行 `变化理由：…` 由脚本保留。生成的补丁立刻过一遍 `bash scripts/patch-surface.sh`——它会告诉你首行丢了、`main.ts` 净增超了、或某个上游文件被两个补丁同时碰了。

需要把文件放进上游树但不想让它出现在补丁里时，用 `assets/` 与 `packaging/`：`apply-patches.sh` 在重放补丁后把它们放到目标位置，`patch-surface.sh` 会拒绝「表格里有的落点又被补丁内嵌」这种重复。

## 改文档

文档规则在 [AGENTS.md](AGENTS.md)——那里定义层级（一个事实只有一个归属）、写作规则、字数预算与废话清单。三条最容易踩的：

- 一段写成一个物理行，不硬折行；折行由渲染器负责。`verify-md-wrap` 会拒。
- 字数预算在 `scripts/doc-budgets.manifest.json`，超了先想办法把内容迁去它该在的层级，再考虑压缩，最后才是提高上限（并在 PR 里写明理由）。
- 会话编号、日期戳、`[x]`/`[ ]` 进度标记不进正文。

## 改决定

决定不是改文档，是写一份新的 Agent Note：`proposed/` 提，落地后移进 `implemented/{class}/`，被否的进 `rejected/`。格式与骨架在 [.agents/notes/README.md](../.agents/notes/README.md)。每份新 note 都触发一次取代检查——同主题的旧 note 要么归档、要么加链接。

## 出包

本地不出包。rpm 由 CI 构建、签名、验收（静态 `verify.sh` + `fedora:44` 容器冒烟）。要验证打包相关改动，先在本地跑 `bash scripts/patch-surface.sh` 与 `bash scripts/verify-shell-syntax.sh`，然后开 PR 让 `patch-gate.yml` 打补丁、跑受影响的上游测试。

容器里 `HOME` 只读时 pnpm 装不上，此时只做 lockfile 静态核对，并在汇报里写「未实测」——不要把静态核对写成已通过。
