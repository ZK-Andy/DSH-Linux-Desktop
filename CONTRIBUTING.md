# 参与

这个仓库是对官方 DSH 桌面客户端的 Linux 打包：上游是外部依赖，我们只提交补丁与围绕补丁的脚本、资产、打包配置，产物是 Fedora x86_64 rpm。

## 先读什么

改补丁之前读 [`docs/architecture.md`](docs/architecture.md)（形状与边界）与 [`PLAN.md`](PLAN.md)（规格）。改文档之前读 [`docs/AGENTS.md`](docs/AGENTS.md)（层级与写作规则）。要改一个已经做过的决定，读 [`.agents/notes/README.md`](.agents/notes/README.md) 再写一份新的 Agent Note。

日常命令在 [`docs/development.md`](docs/development.md)。

## 提交前

```sh
pnpm install
pnpm run check:all
```

门禁在本地跑的就是 CI 的静态那一组。补丁类改动额外确认 `bash scripts/patch-surface.sh` 是绿的。

## 补丁改动的汇报格式

[`AGENTS.md`](AGENTS.md) 要求说明四件事：改了哪个补丁、碰了哪些上游文件且每处是挂钩还是实现、`main.ts` 净增行数、是否产生了重复的事实或组件。PR 描述里照这个写。

## 不要在本地做什么

不要在本地出 rpm——构建、签名、验收都在 CI。不要用 CI 调试本地能验证的问题。不要手工编辑 `patches/*.patch`：补丁由 `scripts/regen-patch.sh` 生成。

## 许可是 MIT

见 [`LICENSE`](LICENSE)。
