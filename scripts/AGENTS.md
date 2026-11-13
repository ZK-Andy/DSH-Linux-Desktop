# scripts/ 子树指令

门禁脚本直接 spawn 外部命令，不经过 shell，仓库相对路径在进入时统一成 `/`。平台差异留在需要它的那个门禁里，不做共享的平台层。

按源码归属做的门禁必须用语法感知的方式发现文件。语料为空或被无意收窄时要报错，不能静默通过——`repo-files.ts` 对不支持的 glob 写法直接抛错，就是这么来的。每种会改变判定边界的准入与排除写法，都补一条测试。

门禁脚本本身遵守 [AGENTS.md](../AGENTS.md) 的规则 1、3、4、9：规矩要么有执行体，要么登记在 [PLAN.md 的待迁移一节](../PLAN.md)。新增检查先问「这条能不能唯一定位一处违规」，定位不了的检查只会变成噪音。

类型与规范由 `tsc --noEmit` 和 `oxlint`（配置在 `.oxlintrc.json`，暂存区版本 `.oxlintrc.staged.json`）管：依赖只在 `package.json` 里声明一次，脚本用 node 直接跑 `.ts`（原生类型剥离），不引 `tsx`。

shell 脚本由 `scripts/verify-shell-syntax.sh` 做语法、渠道判定与可执行位检查，它自己也在门禁里跑。出包相关的脚本（`build.sh`、`smoke-*.sh`、`verify.sh`）只在 CI 里跑，本地不跑全量构建。

流程与命令见 [docs/development.md](../docs/development.md)。
