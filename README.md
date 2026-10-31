# DSH-Linux-Desktop

DeepSeek Harness 官方桌面端的**非官方 Fedora RPM 打包**：fork 官方 `apps/desktop`，叠加 Linux 构建、托盘与更新入口的最小补丁，产出可用 `dnf5` 安装的 `dsh-desktop` 包。

- 客户端本体（UI、Chromium、Host 运行时）全部来自官方 Electron 应用，本项目不重做壳。
- 分发格式只有 RPM（Fedora 44 / dnf5）；更新交给包管理器，应用内只做「检查 → 提示 → 下载 → 一次授权」。
- 不是 DeepSeek 官方项目，与上游无隶属关系。

计划、需求与决策记录以 [PLAN.md](PLAN.md) 为唯一来源；本文只讲「是什么、怎么用」。

## 状态

早期。补丁序列 `0001–0008`（每个补丁一个模块）已在干净的上游 tag 树上重放验证（应用后与改编树逐字节一致），CI 曾成功产出 `dsh-desktop-0.2.2-alpha.2-x86_64.rpm`。托盘在本地 dev 下验证过（SNI + DBusMenu），sharp 桥接也单独验证过，但两者都还没在**装出来的 rpm** 里验收；CI 曾卡在打包冒烟：office 引擎的 Linux 原生包上游未发布，LibreOfficeKit 在 ASAR 下的存在性探测又把缺失包误判为已安装；`0022` 修好探测、让 Linux 回退到随包 WASM 引擎。里程碑见 PLAN.md §5。

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

- `Version` 跟上游 tag：`0.2.2-alpha.2` 映射成 rpm 的 `0.2.2~alpha.2`（`~` 让预发布排在正式版之前）。
- `Release` 是我们自己的打包序号，每次重新打包递增；同一个上游版本重新出包就是 `0.2.2~alpha.2-2`，dnf 据此判定升级。
- git tag 用 `v<上游版本>-<Release>`（如 `v0.2.2-alpha.2-2`），Release 名与 tag 一致。

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

`RPM-GPG-KEY-dsh-desktop` 在仓库 `packaging/` 下，同时随每个 Release 提供（与 rpm、`version.json`、`SHA256SUMS.txt` 一起）。仓库的 repodata 托管在 GitHub Pages（`gh-pages` 分支），rpm 本体仍在版本 Release 里——repodata 的 `<location xml:base>` 指向对应版本的 Release 目录，所以 Pages 上只有索引，不放大文件。

GNOME 默认不显示托盘图标，需要安装并启用扩展：

```bash
sudo dnf5 install gnome-shell-extension-appindicator
gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com
```

新装扩展后可能需要重新登录，托盘才会出现。

## 更新模型

- 包管理器是唯一真源，应用不写 `/usr`、不自更新。
- Releases 上发布 `version.json`（`version` 点分形式、`tag`、rpm 资产名、sha256、字节数）；应用启动后延迟检查一次，托盘「检查更新」与设置页也可手动触发。
- 下载到 `~/.cache/dsh-desktop/`，边下边算 sha256，长度或摘要不符即删除；落盘后再用随包公钥在临时 rpmdb 里 `rpm -Kv` 验签，不通过就不交给安装器。
- 安装经 `pkexec` 调用 `/usr/libexec/dsh-update-helper`（polkit 动作 `org.deepseek.harness.desktop.update`，`allow_active=auth_admin_keep`，授权一次）。helper 只接受缓存目录里的 `dsh-desktop-*.rpm`，先 `rpm --import` 公钥，再 `dnf5 install -y --setopt=localpkg_gpgcheck=1`，日志写 `/var/log/dsh-desktop/update.log`；成功后应用自动重启。
- helper 与 polkit 策略由 rpm `%post` 从 `/opt/deepseek-harness-desktop/resources/` 装到 `/usr/libexec` 与 `/usr/share/polkit-1/actions`，卸载（`%postun` 参数为 0）时移除；应用自身不写 `/usr`。
- dnf 仓库已维护：repodata 在 `gh-pages`（GitHub Pages），rpm 在版本 Release；每次发版用 `scripts/publish-repo.sh` 重生 repodata 并推上去，否则 `dnf5 check-update` 只看到旧版本。

## 构建

CI 跑在 `ubuntu-24.04` 上，装 `rpm`/`xz`/`cpio` 后用 electron-builder 出 rpm；本机没有 `rpmbuild`，出包只走 CI。本地只跑 dev（`./scripts/dev-desktop.sh`）。

两条入口共用 `package.yml`（出包腿：补丁 → 构建 → 签名 → 静态验收 → 容器冒烟）：

- `.github/workflows/build.yml`（周一定时 / 手动）只出包，不碰 Release。
- `.github/workflows/release.yml`（push tag `v*`）出包后聚合资产、生成 `version.json` 与 `SHA256SUMS.txt`、跑 `scripts/release-preflight.sh`（资产矩阵、验签、version.json 与包内事实逐项核对），最后创建 Release。

发版就是打 tag 并推送（tag 尾部的数字即 rpm Release 段）：

```bash
git tag -a v0.2.2-alpha.2-2 -m "DSH Linux Desktop v0.2.2-alpha.2-2"
git push origin v0.2.2-alpha.2-2
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
patches/       # 相对 upstream-tag 的补丁序列（0001–0008，每个补丁一个模块）
assets/        # 补丁装不下的二进制资产（托盘 PNG，由 apply-patches.sh 放到位）
scripts/       # 取上游、打补丁、构建、dev、静态 verify、装包冒烟
docs/          # 调研与说明
.github/workflows/build.yml   # 每周跟版 + workflow_dispatch 出 rpm 并冒烟
```

## 许可

本仓库的补丁与脚本以 MIT 发布；上游 `deepseek-harness` 亦为 MIT，版权归其作者。DSH / DeepSeek Harness 名称与图标归 DeepSeek 所有，本项目仅作非官方分发。
