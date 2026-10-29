# DSH-Linux-Desktop

DeepSeek Harness 官方桌面端的**非官方 Fedora RPM 打包**：fork 官方 `apps/desktop`，只叠加托盘、关闭到托盘与更新入口的补丁，产出可用 `dnf5` 安装的 `dsh-desktop` 包。

- 客户端本体（UI、Chromium、Host 运行时）全部来自官方 Electron 应用，本项目不重做壳。
- 分发格式只有 RPM（Fedora 44 / dnf5）；更新交给包管理器，应用内只做「检查 → 提示 → 下载 → 一次授权」。
- 不是 DeepSeek 官方项目，与上游无隶属关系。

计划、需求与决策记录以 [PLAN.md](PLAN.md) 为唯一来源；本文只讲「是什么、怎么用」。

## 状态

早期。当前只有计划与调研（[docs/linux-packaging-survey.md](docs/linux-packaging-survey.md)），补丁、打包脚本与 CI 尚未落地。里程碑见 PLAN.md §5。

## 需求（验收口径）

| 编号 | 需求 |
|---|---|
| R1 | `dnf5 install ./dsh-desktop-*.rpm` 后应用菜单可见、可启动 |
| R2 | 托盘常驻，菜单含「显示窗口 / 退出」 |
| R3 | 关闭窗口后进程存活、窗口隐藏，只能从托盘退出 |
| R4 | 更新：检查 → 提示 → 下载 → 一次授权 → 安装 → 自动重启 |
| R5 | 自动跟版（每周探测上游 tag）+ 手动触发打包 |

开机自启不在范围内。

## 安装

> 包尚未发布；以下是目标形态。

```bash
sudo dnf5 install ./dsh-desktop-*.rpm
```

GNOME 默认不显示托盘图标，需要安装并启用扩展：

```bash
sudo dnf5 install gnome-shell-extension-appindicator
gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com
```

新装扩展后可能需要重新登录，托盘才会出现。

## 更新模型

- 包管理器是唯一真源，应用不写 `/usr`、不自更新。
- Releases 上发布 `version.json`（版本、rpm 地址、sha256）；应用检查到新版本后下载 rpm，校验签名，经 `pkexec` 调用 `/usr/libexec/dsh-update-helper`，由它执行 `dnf5 install`，完成后应用重启。
- 授权一次（polkit `allow_active`），不要求用户开终端。
- 暂不维护 dnf 仓库；`dnf5 upgrade` 的自动感知留作后续增量（PLAN.md §3.3 B）。

## 构建

> 目标形态；脚本尚未实现。

构建机需要：Node ≥ 24.9、pnpm 11、`rpmbuild`、`xz`。

```bash
./scripts/sync-upstream.sh   # 取上游 tag、应用 patches/
./scripts/build-rpm.sh       # electron-builder --linux rpm
```

产物在 `dist/`，随后由 `scripts/publish-release.sh` 生成 `version.json` 并上传 Release。

## 仓库结构

```
patches/       # 相对固定上游 commit 的补丁序列
packaging/     # rpm spec、polkit 策略、更新 helper
scripts/       # 同步上游、出包、发布
docs/          # 调研与说明
```

## 许可

本仓库的补丁与脚本以 MIT 发布；上游 `deepseek-harness` 亦为 MIT，版权归其作者。DSH / DeepSeek Harness 名称与图标归 DeepSeek 所有，本项目仅作非官方分发。
