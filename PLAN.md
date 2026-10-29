# DSH-Linux-Desktop 计划

本文件是项目计划的唯一来源。调整计划改这里，不在对话里另起一份。

## 1. 定性

- 非官方 Linux 桌面打包：fork `deepseek-ai/deepseek-harness`（MIT）的 `apps/desktop`，只叠加托盘与桌面集成补丁。
- 取代 `dotnet-deepseek-harness-desktop`：.NET 壳停止维护。
- 自用为主，仓库与产物公开（他人可 `dnf5 install` 同一个 rpm）；首要分发格式为 RPM（Fedora 44 / dnf5），构建与更新对包格式解耦。
- 不重做客户端：UI、Chromium 渲染全部来自官方 Electron 应用。

## 2. 需求（硬性，全部闭环）

| 编号 | 需求 | 验收 |
|---|---|---|
| R1 | RPM 可分发包 | `dnf5 install ./dsh-desktop-*.rpm` 后应用菜单可见、可启动 |
| R2 | 托盘常驻 | 托盘图标存在，菜单含「显示窗口 / 退出」 |
| R3 | 关闭到托盘 | 点关闭窗口后进程仍在，窗口隐藏；从托盘退出才结束 |
| R4 | 更新体验对齐旧桌面壳 | 检查 → 提示 → 下载 → 一次授权 → 安装 → 自动重启 |
| R5 | 自动跟版 + 手动触发 | 每周探测上游 `dsh-v*` tag；`workflow_dispatch` 可指定 tag/commit；补丁重放成功才发 Release，失败开 issue 并保留上一版 |

> 原 R3（开机自启）已取消，见 §9 决策记录。

## 3. 架构决定

### 3.1 代码形态

- fork 官方仓库，固定上游 commit，改动以 `patches/NNNN-*.patch` 保存在本仓。
- 补丁只触碰 `apps/desktop` 的主进程入口与窗口生命周期，不扩散到渲染层。
- 初始三个补丁：托盘、关闭到托盘、更新入口（禁用 electron-updater，改读 `version.json`）。

### 3.2 构建

- electron-builder，`linux.target` 只出 `rpm`；不出 AppImage/deb（见 §9）。
- GitHub Actions：`schedule` 每周一 + `workflow_dispatch`（可填上游 tag 或 commit，留空则探测最新 `dsh-v*`）。
- 定时任务在上游 tag 未变时直接退出；手动触发不受此限，用于重试或补发。
- 补丁重放失败：构建失败并自动开 issue，不产出 Release。
- 缓存 pnpm store 与 Electron 下载目录，否则每次构建十几分钟起步。

### 3.3 分发

- 产物上传公开仓库 `DSH-Linux-Desktop` 的 GitHub Releases（单文件上限 2GB）。
- 每个 Release 附 rpm、`version.json`（版本、rpm URL、sha256）、校验和。
- GPG：私钥进 Actions secrets，`rpm --addsign`；公钥安装到 `/etc/pki/rpm-gpg/RPM-GPG-KEY-dsh-desktop`。
- 先做 A：只发 Releases，应用内更新（见 §3.4）。B（dnf 仓库 + `.repo` + `gh-pages` 孤儿分支）作为后续增量，不阻塞 R1–R5。

### 3.4 更新

- 唯一真源是包管理器；应用内不写 `/usr`，不做自更新。
- Releases 上发布 `version.json`：版本号、rpm 地址、sha256。
- 检查时机：启动后延迟一次 + 托盘/应用菜单「检查更新」；不静默下载。
- 流程：检查版本 → 提示 → 下载 rpm 到 `~/.cache/dsh-desktop/` → `rpmkeys --checksig` → `pkexec /usr/libexec/dsh-update-helper` → `dnf5 install <本地 rpm>` → `app.relaunch()` + `app.exit()`。
- helper 与 polkit 策略随包安装，`allow_active` 直接放行一次授权；helper 写日志到 `/var/log/dsh-desktop/update.log`。
- 官方 electron-updater 的下载/安装路径在补丁里禁用，版本检查改为读 `version.json`。

### 3.5 桌面集成

- 托盘：Electron `Tray`，Linux 底层为 AppIndicator；GNOME 需要「AppIndicator and KStatusNotifierItem Support」扩展，写入 README 前置条件。依赖显式声明 `libdbusmenu`（dlopen，`ldd` 看不见，缺了菜单为空）。
- 关闭到托盘：主窗口 `close` 事件里 `preventDefault()` + `hide()`；仅「退出」菜单放行。
- 单实例：`app.requestSingleInstanceLock()`，二次启动聚焦已有窗口。

## 4. 仓库结构

```
DSH-Linux-Desktop/
├── PLAN.md
├── patches/                 # 0001-tray.patch … 上游 tag 一变即可重放
├── packaging/
│   ├── rpm/dsh-desktop.spec
│   ├── polkit/org.dsh.desktop.update.policy
│   └── helper/dsh-update-helper
├── scripts/
│   ├── sync-upstream.sh     # 取 tag、下载源码、应用补丁
│   ├── build-rpm.sh         # electron-builder 出 rpm + 签名
│   └── publish-release.sh   # version.json + Release 资产
├── .github/workflows/build.yml
└── docs/                    # 调研、安装、更新、托盘前置条件、故障排查
```

## 5. 里程碑

- **M1 本地跑通**：克隆上游 tag、应用补丁、`pnpm dev` 出托盘与关闭到托盘。
- **M2 本地出包**：`electron-builder --linux rpm` 成功，`dnf5 install` 后可启动。
- **M3 CI + 自动跟版**：周检上游 tag / 手动 dispatch → 构建 → 签名 → 发 Release。
- **M4 更新链**：`version.json` 检查 → helper → 授权 → 安装 → 重启。
- **M5 收尾**：单实例、GPG 校验、README 前置条件、docs 成文。
- dnf 仓库（B）不进里程碑，M1–M5 完成后再评估。

## 6. 明确不做

- 不做新桌面壳，不内嵌 WebView/CEF；Chromium 由官方 Electron 应用提供。
- 不做应用内自更新。
- 不做开机自启（2026-10-30 取消）。
- 不出 AppImage / deb；AppImage 的自更新路径与 RPM 冲突，不保留。
- 暂不建 dnf 仓库（`.repo` + repodata），先以 Releases 为分发面。
- 不追非 Linux 平台；换发行版只换 `linux.target` 与更新适配器。
- 不维护 .NET 客户端，不在本项目里保留旧壳代码。

## 7. 已知约束

- Fedora 44 默认 dnf5，helper 显式调用 `dnf5`，不依赖 `dnf` 符号链接。
- GNOME 无 AppIndicator 扩展时托盘不可见——文档写明，不作为缺陷处理。
- Wayland 下按上游默认（XWayland 或原生 Wayland），本项目不额外改渲染参数。
- 上游升版即需重放补丁；CI 失败就是「版本落后」的信号，不静默通过。

## 8. 命名

- 仓库目录 / GitHub 公开仓库：`DSH-Linux-Desktop`（大小写一致，不缩写）
- RPM 包名：`dsh-desktop`
- 可执行名：`deepseek-harness`
- 安装前缀：`/opt/deepseek-harness-desktop` + `/usr/bin/deepseek-harness` 符号链接
- desktop 文件：`dsh-desktop.desktop`，`StartupWMClass=deepseek-harness`，`MimeType=x-scheme-handler/dsh`
- 描述：unofficial patched build of the official DSH desktop client for Linux

## 9. 决策记录

| 日期 | 决定 | 理由 |
|---|---|---|
| 2026-10-30 | 放弃 .NET 壳，fork 官方 Electron 客户端 | 渲染体验由引擎层决定，自研壳无法对齐 |
| 2026-10-30 | 更新交给 dnf5，应用内只做提示 | RPM 拥有文件，自更新会破坏包状态 |
| 2026-10-30 | 构建走 CI，产物进 Releases | 不依赖常开机器，日志与产物可追溯 |
| 2026-10-30 | 项目名不含 RPM | 包格式是产物，不是身份 |
| 2026-10-30 | 取消开机自启（原 R3） | 用户明确不要；顺带省掉一条 autostart 补丁与 `%post` 写系统目录 |
| 2026-10-30 | 只出 rpm，不出 AppImage/deb | 单一产物好验收；AppImage 的自更新路径与「更新交给 dnf」相悖 |
| 2026-10-30 | 先走 Releases（A），dnf 仓库（B）后置 | A 不需要静态托管，R1–R5 即可闭环；B 可增量，不改包结构 |
| 2026-10-30 | 仓库名 `DSH-Linux-Desktop`，包名 `dsh-desktop` | 仓库名要大小写一致；包名与可执行名分离，避免与上游 CLI 同名 |
