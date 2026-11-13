# DSH-Linux-Desktop

官方 DSH 桌面客户端的 Linux 打包：fork `deepseek-ai/deepseek-harness`（MIT）的 `apps/desktop`，叠加托盘与桌面集成补丁，产出 Fedora x86_64 rpm。

- 只出 rpm，只支持 x86_64；不出 AppImage / deb。
- 更新只经 dnf 仓库，分 nightly 与 stable 两个渠道；应用不自行下载或安装 rpm。
- 计划与规格见 [PLAN.md](PLAN.md)，架构见 [docs/architecture.md](docs/architecture.md)，决定与备选见 [Agent Notes](.agents/notes/README.md)。

## 状态

上游基线 `dsh-v0.2.2-rc.3`，已跟版、尚未发版。最近一次发版是 `v0.2.2-rc.2-2`（nightly 渠道，rpm `0.2.2~rc.2-2`），双渠道更新链已在真机跑通一次全链闭环。

## 安装

Fedora 44，先导入公钥再装包：

```sh
sudo rpm --import https://github.com/ZK-Andy/DSH-Linux-Desktop/releases/latest/download/RPM-GPG-KEY-dsh-desktop
sudo dnf5 install ./dsh-desktop-*.rpm
```

要跟随更新，装一次 dnf 仓库然后在设置页选渠道：

```sh
sudo dnf5 config-manager addrepo --from-repofile=https://zk-andy.github.io/DSH-Linux-Desktop/dsh-desktop.repo
sudo dnf5 install dsh-desktop
```

GNOME 需要「AppIndicator and KStatusNotifierItem Support」扩展，否则托盘不可见——这不是缺陷。

## 更新

应用内「检查更新」走随包的 dnf 仓库：`dnf5 repoquery --upgrades` 读到候选版本，提示后用 `pkexec /usr/libexec/dsh-update-helper` 请求一次授权，helper 执行一条 `dnf5 upgrade`，成功才重启应用。签名与完整性由 dnf 的 gpgcheck 负责，应用不下载、不校验、不缓存 rpm。

渠道判定：发布 tag 的版本含预发布标记（`~`、`-rc`、alpha、beta 等）→ nightly；正式版 → stable 且同时进 nightly。随包 `.repo` 里 stable section 是 `enabled=1`、nightly 是 `enabled=0`，所以手动 `dnf5` 默认只走 stable；应用内按设置页选的渠道显式启用对应 repo。

从 nightly 切回 stable 后，正式版追平之前会显示「已是最新」——dnf 语义不降级，这是预期行为。

## 故障排查

更新失败时，详情写在应用日志目录的 `update-failures.log`（候选与当前版本、退出码、helper 输出末 10 行）。helper 日志在 `/var/log/dsh-desktop/update.log`。

退出码 127 表示 pkexec 在授权前就失败了，多半是启动应用的进程带了污染的环境变量。彻底退出应用再从桌面重新打开——托盘里的「重启」用 `app.relaunch()` 继承旧环境，治不了这个。

## 构建

rpm 由 CI 构建、签名、验收，本地不出包。本地只跑开发：

```sh
pnpm install
bash scripts/dev-desktop.sh
```

给贡献者的流程见 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [docs/development.md](docs/development.md)。

## 许可

MIT，见 [LICENSE](LICENSE)。上游客户端版权归 DeepSeek 所有；本项目只是打包。
