# DSH-Linux-Desktop

DeepSeek Harness 官方桌面端的**非官方 Fedora RPM 打包**：fork 官方 `apps/desktop`，叠加 Linux 构建、托盘与更新入口的最小补丁，产出可用 `dnf5` 安装的 `dsh-desktop` 包。

- 客户端本体（UI、Chromium、Host 运行时）全部来自官方 Electron 应用，本项目不重做壳。
- 分发格式只有 RPM（Fedora 44 / dnf5）；更新交给包管理器，应用内只做「检查 → 提示 → 下载 → 一次授权」。
- 不是 DeepSeek 官方项目，与上游无隶属关系。

计划、需求与决策记录以 [PLAN.md](PLAN.md) 为唯一来源；本文只讲「是什么、怎么用」。

## 状态

补丁序列 `0001–0009`、`0011`（每个补丁一个模块；`0010` 已随上游 rc.2 删除）已在上游 `dsh-v0.2.2-rc.2` 的干净树上重放通过：`patch-surface.sh` 静态断言、全量 `apply-patches.sh`（无 `.rej`）、`pnpm install --frozen-lockfile`、类型门与 8 个定向单测均在本机通过；rpm 构建与安装验收只走 CI（本机没有 rpmbuild），留待 CI 与真机。已发版至 `v0.2.2-alpha.3-3`，托盘与更新链路已在装出来的 rpm 上实机验收通过。里程碑见 PLAN.md §5。

## 需求（验收口径）

| 编号 | 需求 |
|---|---|
| R1 | `dnf5 install ./dsh-desktop-*.rpm` 后应用菜单可见、可启动 |
| R2 | 托盘常驻，菜单含「显示窗口 / 退出」 |
| R3 | 关闭窗口后进程存活、窗口隐藏，只能从托盘退出 |
| R4 | 更新：检查 → 提示 → 下载 → 一次授权 → 安装 → 自动重启 |
| R5 | 自动跟版（每周探测上游 tag）+ 手动触发打包 |

开机自启不在范围内。

## 版本号规则

- `Version` 跟上游 tag：`0.2.2-rc.2` 映射成 rpm 的 `0.2.2~rc.2`（`~` 让预发布排在正式版之前）。
- `Release` 是我们自己的打包序号，每次重新打包递增；同一个上游版本重新出包就是 `0.2.2~rc.2-2`，dnf 据此判定升级。
- git tag 用 `v<上游版本>-<Release>`（如 `v0.2.2-rc.2-2`），Release 名与 tag 一致。

## 安装

rpm 用仓库的 GPG 密钥签名。两种方式，推荐第一种（之后 `dnf5 upgrade` 能跟着系统一起升级）：

```bash
# 方式一：从 dnf 仓库安装
sudo rpm --import https://github.com/ZK-Andy/DSH-Linux-Desktop/releases/latest/download/RPM-GPG-KEY-dsh-desktop
sudo curl -fsSL https://zk-andy.github.io/DSH-Linux-Desktop/dsh-desktop.repo -o /etc/yum.repos.d/dsh-desktop.repo
sudo dnf5 install dsh-desktop

# 方式二：直接装 Release 里的 rpm
sudo rpm --import ./RPM-GPG-KEY-dsh-desktop
sudo dnf5 install ./dsh-desktop-*.rpm
```

`RPM-GPG-KEY-dsh-desktop` 在仓库 `packaging/` 下，同时随每个 Release 提供（与 rpm、`SHA256SUMS.txt` 一起）。仓库的 repodata 托管在 GitHub Pages（`gh-pages` 分支），rpm 本体仍在版本 Release 里——repodata 的 `<location xml:base>` 指向对应版本的 Release 目录，所以 Pages 上只有索引，不放大文件。

GNOME 默认不显示托盘图标，需要安装并启用扩展：

```bash
sudo dnf5 install gnome-shell-extension-appindicator
gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com
```

新装扩展后可能需要重新登录，托盘才会出现。

## 更新模型

- 包管理器是唯一真源，应用不写 `/usr`、不自更新、不自带下载器。
- **更新渠道（nightly / stable）**：仓库分两个渠道——stable 只收正式版，nightly 收预发布、正式版同时进 nightly。应用默认 nightly（渠道状态存于上游 settings，设置页可切）；切换只影响检查/安装时查哪个仓库，不改变已装版本，dnf 语义不降级；从 nightly 切回 stable 后，正式版追平前显示「已是最新」。手动 `sudo dnf5 upgrade dsh-desktop` 只走 stable（nightly 的 section 默认 `enabled=0`）。
- 检查更新：`dnf5 repoquery --upgrades --queryformat '%{evr}\n' --setopt=dsh-desktop.skip_if_unavailable=0 dsh-desktop`（应用按渠道显式 `--enablerepo` / `--disablerepo`；nightly 默认 disabled，手动命令不加就看不到预发布）。有输出即有新版本，空输出即已是最新，命令失败则原样展示错误；启动后延迟检查一次，托盘「检查更新」与设置页可手动触发（手动时带 `--refresh`）。
- 安装：`pkexec /usr/libexec/dsh-update-helper`（polkit 动作 `org.deepseek.harness.desktop.update`，对本机用户直接放行、不依赖 logind 会话或认证代理——COSMIC 等桌面以 systemd 用户 scope 启动应用时，应用进程没有会话，按会话放行的策略会静默拒绝；代价是本机任何用户都能触发一次从签名仓库的升级，但 helper 只做固定动作，拿不到任意 root 执行）。spawn 只给 pkexec 设 `LC_ALL=C`：pkexec 会把 helper 的环境重置为最小安全集，真正要守的是 pkexec 自己的 polkit 连接（GDBus 读 `DBUS_SYSTEM_BUS_ADDRESS`），实例级的环境污染不再能打断授权，系统总线固定走默认 socket（真机验证过 `env -i LC_ALL=C` 下全链成功，PATH/HOME 都不需要）。helper 只接受可选参数 `--channel=nightly|stable`（只此一个；非法 64、非 root 77、公钥导入失败 70），无参 = nightly，只执行一条 `dnf5 upgrade -y --refresh <所选渠道的 repo 参数> dsh-desktop`，显式启用所选渠道、禁用另一渠道；仓库文件里是 `skip_if_unavailable=1`，helper 不覆盖该开关（仓库不可达的可见性由应用侧检查负责，它显式关掉此项以便报错），日志写 `/var/log/dsh-desktop/update.log`；helper 在应用运行中升级，成功后应用停 Host 再重启，失败则保持运行并显示错误，不自动重启，失败详情（候选与当前版本、退出码与 helper 输出末 10 行）追加写入应用日志目录的 `update-failures.log`（文件 0600）。
- **安装报「helper 退出码 127」**：这是 pkexec 自身失败——未获授权、出错或 helper 无法执行（认证对话框被取消才是 126），helper 没有运行。失败详情已写入应用日志目录的 `update-failures.log`（含候选与当前版本）。pkexec 失败不留系统日志；个别应用实例的进程环境被污染时会出现，且托盘「重启」（`app.relaunch()`，继承旧环境）治不了——**彻底退出应用后从桌面重新打开**再装即可；若日志显示的是 exec 类错误（权限、noexec 挂载、SELinux），重开应用无效，需按日志另行排查。
- **从旧策略升上来的机器需要一次性旁路**：alpha.2 与 alpha.3-1 的 rpm 携带的是旧 polkit 策略（按会话放行），应用内更新会被静默拒绝；先 `sudo dnf5 upgrade --refresh dsh-desktop` 装上带修复的版本，之后的应用内更新才会走通。
- 版本比较：应用把安装的 rpm `VERSION-RELEASE` 编码成 semver 再比（预发布 `0.2.2~rc.2-6` → `0.2.2-rc.2.6`，正式版 `0.2.3-1` → `0.2.3.z.1`），所以第 10 个 release 不会被当成比第 9 个旧。
- helper、polkit 策略、`/etc/yum.repos.d/dsh-desktop.repo`、公钥 `/etc/pki/rpm-gpg/RPM-GPG-KEY-dsh-desktop` 与日志目录 `/var/log/dsh-desktop` 都由 rpm 文件清单直接拥有（fpm 的 `源=目标` 映射）；`.repo` 标 `%config(noreplace)`，`%post` 只做一次幂等 `rpm --import`，`%postun` 在卸载（参数 0）时删掉随包公钥。
- dnf 仓库已维护：repodata 在 `gh-pages`（GitHub Pages），rpm 在版本 Release；每次发版用 `scripts/publish-repo.sh` 重生 repodata 并推上去，否则 `dnf5 check-update` 只看到旧版本。

## 构建

CI 跑在 `ubuntu-24.04` 上，装 `rpm`/`xz`/`cpio` 后用 electron-builder 出 rpm；本机没有 `rpmbuild`，出包只走 CI。本地只跑 dev（`./scripts/dev-desktop.sh`）。

两条入口共用 `package.yml`（出包腿：补丁 → 构建 → 签名 → 静态验收 → 容器冒烟）：

- `.github/workflows/build.yml`（周一定时 / 手动）只出包，不碰 Release。
- `.github/workflows/release.yml`（push tag `v*`）出包后聚合资产、生成 `SHA256SUMS.txt`、跑 `scripts/release-preflight.sh`（资产矩阵、验签、校验和自洽），最后创建 Release 并刷新 gh-pages 的 repodata。

发版就是打 tag 并推送（tag 尾部的数字即 rpm Release 段）：

```bash
git tag -a v0.2.2-rc.2-1 -m "DSH Linux Desktop v0.2.2-rc.2-1"
git push origin v0.2.2-rc.2-1
```


```bash
./scripts/fetch-upstream.sh     # 按 upstream-tag 浅克隆到 upstream/
./scripts/apply-patches.sh      # 打进 patches/*.patch，并放置托盘 PNG
(cd upstream && pnpm install --frozen-lockfile)
./scripts/build.sh --rpm        # 默认就是 --rpm；--dir 只出未打包目录
./scripts/verify.sh dist/*.rpm  # 静态验收：包名/版本/依赖/布局/desktop 入口/%post
```

产物在 `upstream/apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/`，文件名 `dsh-desktop-<version>-x86_64.rpm`（electron-builder 原始名带 `-unsigned`，CI 收集时去掉，因为签名在收集之后），CI 用 `rpmsign` 加签（私钥在 Actions secrets，公钥 `packaging/RPM-GPG-KEY-dsh-desktop`）。安装后的验收是 `scripts/smoke-install-rpm.sh`：在 `fedora:44` 容器里先导入公钥、`rpmkeys -K` 验签，再以 `localpkg_gpgcheck=1` `dnf5 install`、`xvfb` 启动、`xdotool` 确认窗口、截图留档；截图与 `app.log` 经 `SMOKE_SHOT_DIR`/`SMOKE_LOG_DIR` 落到宿主并上传 artifact（跑过且失败判 error，其余 warn）。

本地调试窗口（不打包）：

```bash
./scripts/dev-desktop.sh
```

## 仓库结构

```
patches/       # 相对 upstream-tag 的补丁序列（0001–0009、0011，每个补丁一个模块）
assets/        # 补丁装不下的二进制资产（托盘 PNG，由 apply-patches.sh 放到位）
scripts/       # 取上游、打补丁、构建、dev、静态 verify、装包冒烟
docs/          # 调研与说明
.github/workflows/build.yml   # 每周跟版 + workflow_dispatch 出 rpm 并冒烟
```

## 许可

本仓库的补丁与脚本以 MIT 发布；上游 `deepseek-harness` 亦为 MIT，版权归其作者。DSH / DeepSeek Harness 名称与图标归 DeepSeek 所有，本项目仅作非官方分发。
