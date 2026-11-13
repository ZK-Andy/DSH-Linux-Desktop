# .github/ 子树指令

四个工作流各管一段，别让职责交叉：

- `build.yml`：每周跟版 + 手动触发，只出包，不创建 Release。
- `package.yml`：可复用的出包作业，`build.yml` 与 `release.yml` 都调它。Node 与 pnpm 的版本唯一来源是 `actions/setup-node-pnpm`，升版只改那里；缓存不放在 action 里。
- `patch-gate.yml`：只在 `pull_request` 上跑，先跑门禁，再从改动的补丁推出该跑哪些上游测试。
- `release.yml`：打 tag 时跑，先出包，再发 Release，最后刷新 `gh-pages` 上的 repodata。

`patch-gate.yml` 的 `jobs.<id>.name` 会被分支保护规则当作必需检查引用，改名等于让那些规则失效——真要改名，同一次改动里改仓库设置。

出包作业里的每一步都在真机上验证过才能删。删「Free disk space」会让 90 分钟超时变成磁盘不足；删 `--checksum` 会让新旧签名字节数相同时跳过 `.asc`，直到用户看到 `Bad PGP signature`。

密钥只经 `secrets` 进环境，不落到文件、不进日志。sign 步骤缺密钥必须失败，不能降级成未签名产物。
