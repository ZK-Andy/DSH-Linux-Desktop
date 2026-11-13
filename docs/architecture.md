# 架构

改 `patches/` 之前先读本文。本文只讲形状与边界，具体规格在 [PLAN.md](../PLAN.md)，决定与备选在 [Agent Notes](../.agents/notes/README.md)。

## 构成

上游客户端是外部依赖，不是我们的代码；我们只提交补丁与围绕补丁的脚本、资产、打包配置。产物是 Fedora x86_64 rpm，主要维护成本是上游升版后重放补丁。这个形状决定了所有取舍：能写进新文件的绝不改上游文件，能由脚本放置的绝不内嵌进补丁。

```
上游 tarball ──fetch-upstream.sh──▶ upstream/
                                      │ apply-patches.sh（含 assets/ 放置）
                                      ▼
                          upstream/（已打补丁的工作树）
                                      │ build.sh --rpm
                                      ▼
                              dist/*.rpm ──verify.sh / smoke-install-rpm.sh
                                      │ release.yml
                                      ▼
                        GitHub Releases + gh-pages repodata
```

## 依赖方向

高层是领域概念——补丁、资产、渠道、更新链。低层是外部系统——electron-builder、rpmbuild、dnf5、polkit。外部系统的概念在边缘翻译成我们的概念，不进入核心：dnf 的退出码在 helper 里翻译成 64/77/70，electron-builder 的 `productName` 在打包配置里翻译成四个身份名，都不外溢到别处。

一条推论：脚本只经由少而稳定的接口互相调用（`upstream-tag`、`dist/`、环境变量），换掉某一个脚本的实现，调用方不必改。

## 补丁体系

补丁是唯一承载上游改动的容器。一条补丁对应一个变化理由，首行写 `变化理由：…`，由 [`scripts/regen-patch.sh`](../scripts/regen-patch.sh) 保留。

**实现写在新文件。** 上游已有文件只加挂钩：一个 import、一处调用、一处对象展开、必要的类型扩展。新文件的命名按领域取名（`linux-window.ts`、`update-install-handoff.ts`），不按技术层取名。

**一个上游文件只归一个补丁**，`main.ts` 除外——它是唯一的汇合点，每条补丁都可能要在那里挂一行。因此 `main.ts` 的净增要单独记账：每条补丁不超过 15 行，超过时在首行之后写 `例外：规则 4，<原因>；待迁移：<条目名或「否」>`，例外只给确实搬不走的代码。

**每个事实只在一处。** 二进制与系统文件放 [`assets/`](../assets)、[`packaging/`](../packaging)，由 `scripts/apply-patches.sh` 放置，补丁不内嵌副本；rpm Release 号只来自 CI 环境变量；命名以 PLAN.md 为准。

判断拆分对不对，只看一次改动碰几个补丁、几个上游文件，不看补丁多长。参考项目的写法与本节冲突时，采用其行为、按本节放置代码，并在汇报里说明。

## 规则有执行体

规则 1、3、4、9 由 [`scripts/patch-surface.sh`](../scripts/patch-surface.sh) 对 `patches/` 做静态断言，在重放补丁前运行。豁免的登记处只有 PLAN.md 的待迁移一节：检查只在「能唯一定位这一条违规」的字符串命中时才算已登记，条目删除后检查自动变硬。

现状与规则不一致之处也登记在那里。已列入的按条目收拢，未列入的按缺陷处理；新改动不得扩大差距——条目涉及的上游文件，触碰它的补丁数不得上升，行数上升要写例外并说明是修缺陷还是新增实现。

## 运行时形态

Host 由 Electron 以 node 模式托管，不换独立 Node，asar 保持开启，与官方 macOS/Windows 形态一致。两个 Linux 特有的失败因此分头解决：sharp 移进子进程（进程隔离），窗口与托盘在渲染层与主进程各新增一层（补丁隔离）。细节见 [Agent Notes](../.agents/notes/README.md) 里的对应条目。

## 更新链

应用不碰 `/opt` 与 `/usr`——那里的文件归 rpm 所有。应用只做三件事：用 `dnf5 repoquery --upgrades` 发现版本、用 `pkexec /usr/libexec/dsh-update-helper` 请求安装、把 helper 的输出翻译成界面状态。渠道是 repo 的 `enabled` 开关，不是应用里的模式。完整语义（退出码、双 section、迁移兼容）在 [PLAN.md](../PLAN.md)。
