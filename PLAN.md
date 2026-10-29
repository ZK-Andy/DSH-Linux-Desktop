# DSH-Linux-Desktop 计划

本文件是项目计划的唯一来源。调整计划改这里，不在对话里另起一份。

## 1. 定性

- 非官方 Linux 桌面打包：fork `deepseek-ai/deepseek-harness`（MIT）的 `apps/desktop`，只叠加托盘与桌面集成补丁。
- 取代 `dotnet-deepseek-harness-desktop`：.NET 壳停止维护。
- 自用为主，仓库与产物公开（他人可 `dnf5 install` 同一个 rpm）；交付物只有 RPM（Fedora 44 / dnf5）。
- 不重做客户端：UI、Chromium 渲染全部来自官方 Electron 应用。

## 2. 需求（硬性，全部闭环）

| 编号 | 需求 | 验收 |
|---|---|---|
| R1 | RPM 可分发包 | 公钥已导入（§3.3）后，`dnf5 install ./dsh-desktop-*.rpm` 成功，应用菜单可见、可启动 |
| R2 | 托盘常驻 | 托盘图标存在，菜单含「显示窗口 / 退出」；在 Fedora 44 GNOME Wayland（装 AppIndicator 扩展）上人工确认 |
| R3 | 关闭到托盘 | 点关闭窗口后进程仍在，窗口隐藏；从托盘退出才结束 |
| R4 | 更新体验对齐旧桌面壳 | 检查 → 提示 → 下载 → 一次授权 → 安装 → 自动重启 |
| R5 | 自动跟版 + 手动触发 | 每周探测上游 `dsh-v*` tag；`workflow_dispatch` 可指定 tag/commit；补丁重放成功才发 Release，失败开 issue 并保留上一版 |

> 原 R3（开机自启）已取消，见 §9 决策记录。

## 3. 架构决定

### 3.1 代码形态

- fork 官方仓库，固定上游 commit，改动以 `patches/NNNN-*.patch` 保存在本仓。
- 补丁只触碰 `apps/desktop` 的主进程入口、构建配置与窗口生命周期，不扩散到渲染层。**例外**：`packages/attachment/attachment-local/src/sharp.ts` 是 Linux 可运行性的前提（见 §3.6），允许改这一处。
- 初始四条补丁：`0001-linux-build`（electron-builder 配置）、`0002-tray`、`0003-update`、`0004-sharp-isolation`。
- **关闭到托盘与单实例不写补丁**：上游 `apps/desktop/src/main.ts:1173-1188` 已无条件 `preventDefault()+hide()`；单实例在 `apps/desktop/src/single-instance.ts`（`claimDesktopSingleInstance`）。本项目的 R3 由上游行为满足，补丁只补托盘入口。
- 补丁以「可重放」为准：上游 tag 一变就重生成，不为通过而调 fuzz。

### 3.2 构建

- electron-builder（上游已用 26.17），`linux.target` 只出 `rpm`：不出 AppImage/deb，不保留任何其它 Linux 产物。
- 构建配置由 `0001-linux-build.patch` 落地：`target: ['rpm']`、`packageName`、`executableName`、`productName`/`desktopName`、图标、`artifactName`、`asarUnpack`、`extraResources`（托盘 PNG、sharp worker）、`afterInstall` 脚本（见 §3.7）。
- `artifactName` 定为 `dsh-desktop-${version}-${arch}.${ext}`，与 R1 的 `dsh-desktop-*.rpm` 对齐。
- 预发布版本映射：`dsh-v0.2.2-alpha.2` → rpm `0.2.2~alpha.2`。M2 用 `rpm -qp --qf '%{VERSION}-%{RELEASE}'` 实测钉死，`version.json` 与 rpm 用同一套映射。
- GitHub Actions：`container: fedora:44`（rpmbuild、xz、xvfb、Electron 运行库都在里面装齐），`schedule` 每周一 + `workflow_dispatch`（可填上游 tag 或 commit，留空则探测最新 `dsh-v*`）。
- 定时任务在上游 tag 未变时直接退出；手动触发不受此限，用于重试或补发。
- 补丁重放失败：构建失败并自动开 issue，不产出 Release。
- 缓存：pnpm store（`~/.local/share/pnpm/store`）、Electron 下载目录（`~/.cache/electron`）、上游源码 tarball；缓存 key 含上游 tag；不缓存 `node_modules`。
- 冒烟：出包后在 `xvfb` 下安装并启动应用，抓主进程日志并截图（`import` → `scrot` 级联，失败不拦），截图与日志上传 artifact；崩溃或没建出托盘判失败。另用 D-Bus 查 `StatusNotifierItem` 注册，证明托盘对象真的挂上去了。
- CI 证明不了 GNOME 里的可见性：R2 以真实 GNOME Wayland 人工验收为准，CI 只保证对象与注册存在。

### 3.3 分发

- 产物上传公开仓库 `DSH-Linux-Desktop` 的 GitHub Releases（单文件上限 2GB）。
- 每个 Release 附 rpm、`version.json`（版本、rpm URL、sha256）、公钥 `RPM-GPG-KEY-dsh-desktop`。
- GPG：私钥进 Actions secrets，`rpm --addsign`；公钥随包安装到 `/etc/pki/rpm-gpg/RPM-GPG-KEY-dsh-desktop`，并在 Release 里单列一份。
- **首装公钥**：`dnf5` 校验签名需要 rpmdb 里有公钥，因此 README 的首装命令是两步——先 `sudo rpm --import https://github.com/ZK-Andy/DSH-Linux-Desktop/releases/latest/download/RPM-GPG-KEY-dsh-desktop`，再 `dnf5 install ./dsh-desktop-*.rpm`。这是第三方签名 rpm 的标准做法，不是临时绕行；更新链由 helper 自动 import，不再需要用户手动做。
- 先做 A：只发 Releases，应用内更新（见 §3.4）。B（dnf 仓库 + `.repo` + `gh-pages` 孤儿分支）作为后续增量，不阻塞 R1–R5。

### 3.4 更新

- 唯一真源是包管理器；应用内不写 `/usr`，不做自更新。
- **复用官方更新 UI**：改 `apps/desktop/src/update-coordinator.ts` 的状态机（:54 目前直接 `new autoUpdater`，:55 依赖 `app-update.yml`），保留 `update-dialog` / `update-presentation` 的渲染层契约，不另做原生 dialog，不搞两套更新界面。
- 检查源：`https://github.com/ZK-Andy/DSH-Linux-Desktop/releases/latest/download/version.json`（走重定向，不碰 API 限流）；`version.json` 含版本号、rpm 地址、sha256。
- 检查时机：启动后延迟一次 + 托盘/应用菜单「检查更新」；不静默下载。
- 流程：检查版本 → 提示 → 下载 rpm 到 `~/.cache/dsh-desktop/` → 校验 sha256 → `rpmkeys --checksig` → `pkexec /usr/libexec/dsh-update-helper` → helper 先 `rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-dsh-desktop` → `dnf5 install <本地 rpm>` → `app.relaunch()` + `app.exit()`。
- helper 与 polkit 策略随包安装，`allow_active` 直接放行一次授权；helper 写日志到 `/var/log/dsh-desktop/update.log`。
- electron-updater 的下载/安装路径在补丁里整体替换（不是「禁用后另开一路」），避免两套状态机并存。

### 3.5 桌面集成

- 托盘：上游 `DesktopTray`（`apps/desktop/src/tray.ts`）本身跨平台，补丁只做三件事——把 `main.ts:1088-1094` 的 `win32` 门放宽到 Linux、把 `main.ts:1087` 的 `.ico` 路径换成 PNG、为打包补 `resources/tray.png`（由 `scripts/render-tray-icon.ts` 的同一 SVG 源生成，构建期纯 Node 跑 sharp）。
- GNOME 需要「AppIndicator and KStatusNotifierItem Support」扩展，写入 README 前置条件。依赖显式声明 `libdbusmenu`（Fedora 有同名包；dlopen，`ldd` 看不见，缺了菜单为空）。
- 关闭到托盘、单实例：沿用上游，不重复实现（§3.1）。
- 运行时保持官方形态：Host 由 Electron 以 node 模式托管（`ELECTRON_RUN_AS_NODE=1`），**不替换成独立 Node**。参考项目 issue #8 里插件市场卡在「安装中」、后续 409，正是把 Host 换成独立 Node 后热挂载/重启握手失败所致；ASAR 也随官方保留开启。

### 3.6 图片解码（sharp 隔离）

- **问题**：Electron 在 Linux 上把 sharp/libvips 加载进自己的进程，会因 glib 断言失败直接 `abort()`（[electron#46323](https://github.com/electron/electron/issues/46323)）。官方运行时下，`read_image` 或把图片作为附件发送，会把整个 Host 弄崩，重启后回到同一会话仍复现（[Zhou #24](https://github.com/Zhou-Yujing114514/deepseek-harness-linux/issues/24)）。
- **已知的两条半解**：整体换独立 Node → 图片正常、插件市场坏（[ffyfox #8](https://github.com/ffyfox/dsh-desktop-linux/issues/8)）；保持官方运行时 → 市场正常、图片崩（Zhou #24）。两者不能只选其一。
- **做法**：Host 留在 Electron node 模式；sharp 移出 Electron 进程，放进由打包内 `resources/runtime/primary-runtime/dependencies/node` 启动的子进程，Host 通过 IPC 调用。子进程用打包自带 Node，不依赖系统 node。
- **打包前提**（补丁里一并做，否则真 Node 加载不了）：
  - worker 脚本走 `extraResources`（asar 外），例如 `resources/sharp-worker.cjs`；
  - `sharp` 与 `@img/**` 加进 `asarUnpack`；worker 用 `app.asar.unpacked` 下的绝对路径 `require`，不靠模块解析；
  - dev 模式没有 primary-runtime node，回退到 `PATH` 里的 `node`（仅 dev），否则本地 `pnpm dev` 直接坏。
- **补丁点**：`packages/attachment/attachment-local/src/sharp.ts` 里的 `requireSharp`（`createLazyRequire<typeof sharp>('sharp', import.meta.url)`）是全部图片处理的唯一入口，只改这一处；`image.ts` / `normalization.ts` / `encoding.ts` 不动。
- **失败行为**：子进程崩溃只让当次调用失败，Host 存活并返回明确错误；不再出现「贴一张图，应用退出」。
- **验收**：以 #24 的复现场景为准（`read_image` 读本地 PNG、粘贴图片附件）；CI 冒烟加一条真实解码断言，上游升级后第一个暴露问题。
- **不采用**：整体替换 Host 运行时（会把市场问题引进来），或用「不显示图片」降级。

### 3.7 打包身份与安装布局

- `productName: "deepseek-harness-desktop"` → `/opt/deepseek-harness-desktop`（electron-builder 的 `/opt` 目录由 `productFilename` 派生，不另写 afterPack）。
- `executableName: "deepseek-harness"` → `/usr/bin/deepseek-harness` 符号链接与进程名。
- `packageName: "dsh-desktop"` → rpm 的 `Name`。
- `desktopName: "dsh-desktop"` + `linux.syncDesktopName: true` → 安装后的 `dsh-desktop.desktop`；`StartupWMClass` 以 M2 实测的 `xprop WM_CLASS` 为准钉死（Electron 版本间有差异），并同步回本计划。
- 图标：给 `linux.icon` 指定 1024×1024 PNG（复用 `resources/icon-windows.png` 或新增 `icon-linux.png`），electron-builder 自动铺 hicolor。
- `afterInstall` 脚本负责：`unshare --user true` 可用则 `chrome-sandbox` 0755、否则 4755；`update-desktop-database`；`gtk-update-icon-cache`。
- `Requires` 覆盖默认集时保留 gtk3/nss/libnotify 等，并显式加 `libdbusmenu`；`libxcrypt-compat` 仅在 primary-runtime 带 Python 时加（M2 用 `rpm -qpR` 复核）。

## 4. 仓库结构

```
DSH-Linux-Desktop/
├── PLAN.md
├── patches/                 # 0001-linux-build … 上游 tag 一变即可重放
├── packaging/
│   ├── after-install.sh     # chrome-sandbox / desktop-database / icon-cache
│   ├── polkit/org.dsh.desktop.update.policy
│   ├── helper/dsh-update-helper
│   └── gpg/RPM-GPG-KEY-dsh-desktop
├── scripts/
│   ├── sync-upstream.sh     # 取 tag、下载源码、应用补丁
│   ├── apply-patches.sh     # git apply --check / 重放
│   ├── build-rpm.sh         # electron-builder 出 rpm + 签名
│   └── publish-release.sh   # version.json + Release 资产
├── .github/workflows/build.yml
└── docs/                    # 调研、安装、更新、托盘前置条件、故障排查
```

## 5. 里程碑

- **M1 本地跑通（dev）**：克隆上游 tag、应用补丁、`pnpm dev` 看到托盘、关窗隐藏后能召回，并验证 sharp 隔离后 `read_image`/图片附件不再崩 Host（只验行为，不出包）。
- **M2 CI 出包**：CI 构建 rpm（含冒烟截图与 SNI 检查），`dnf5 install` 产物后可启动；实测并钉死版本映射、`/opt` 路径、`WM_CLASS` 与依赖。
- **M3 CI + 自动跟版**：周检上游 tag / 手动 dispatch → 构建 → 签名 → 发 Release。
- **M4 更新链**：`version.json` 检查 → 官方更新 UI → 下载 → helper → 授权 → 安装 → 重启。
- **M5 收尾**：单实例复核、GPG 校验、README 前置条件、docs 成文。
- dnf 仓库（B）不进里程碑，M1–M5 完成后再评估。

## 6. 明确不做

- 不做新桌面壳，不内嵌 WebView/CEF；Chromium 由官方 Electron 应用提供。
- 不做应用内自更新。
- 不做开机自启（2026-10-30 取消）。
- 不出 AppImage / deb / zip；AppImage 的自更新路径与 RPM 冲突，不保留。
- 不做「原生 dialog 版更新入口」的过渡实现，也不做两套更新界面。
- 暂不建 dnf 仓库（`.repo` + repodata），先以 Releases 为分发面。
- 不追非 Linux 平台；换发行版只换 `linux.target` 与更新适配器。
- 不维护 .NET 客户端，不在本项目里保留旧壳代码。
- 不替换 Host 运行时（不引入独立 Node、不因此关 ASAR）。
- 不在 Electron 进程内加载 sharp（Linux 一律走 §3.6 的子进程）。

## 7. 已知约束

- Fedora 44 默认 dnf5，helper 显式调用 `dnf5`，不依赖 `dnf` 符号链接。
- GNOME 无 AppIndicator 扩展时托盘不可见——文档写明，不作为缺陷处理。
- Wayland 下按上游默认（XWayland 或原生 Wayland），本项目不额外改渲染参数。
- 上游升版即需重放补丁；CI 失败就是「版本落后」的信号，不静默通过。
- Electron 与 libvips 的 glib 冲突是上游未修的问题（electron#46323 仍 open），只能靠 §3.6 的隔离规避；上游哪天修了，隔离补丁可以单独摘掉。
- 首装须一次性导入公钥（§3.3）；不导入时 `dnf5` 会以 NOKEY 拒绝签名包。
- `/opt` 目录名、desktop 文件名、`WM_CLASS` 由 `productName`/`desktopName` 与 Electron 版本共同决定，M2 实测后以实测值为准。

## 8. 命名

- 仓库目录 / GitHub 公开仓库：`DSH-Linux-Desktop`（大小写一致，不缩写）
- RPM 包名（`Name`）：`dsh-desktop`
- `productName` / `/opt` 目录：`deepseek-harness-desktop`
- 可执行名：`deepseek-harness`（`/usr/bin/deepseek-harness` 符号链接）
- `desktopName` / desktop 文件：`dsh-desktop` / `dsh-desktop.desktop`
- `StartupWMClass`：以 M2 实测 `WM_CLASS` 为准（预期 `dsh-desktop`）
- `MimeType=x-scheme-handler/dsh`
- 产物名：`dsh-desktop-<version>-<arch>.rpm`
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
| 2026-10-30 | Host 保持官方 Electron node 模式，不换独立 Node | 参考项目 issue #8：换独立 Node 后插件市场热挂载/重启握手失败、UI 卡「安装中」并 409；官方形态在 Win/Mac 已验证 |
| 2026-10-30 | sharp 隔离到子进程，写进 M1 | Electron 进程内加载 libvips 在 Linux 会 abort（electron#46323、Zhou #24）；独立 Node 跑 sharp 正常（ffyfox #8 实测），把这两段拼起来即可，不依赖逐步试错 |
| 2026-10-30 | 本地只跑 dev 调补丁，出包与发版全在 CI | 补丁迭代要快；rpm 构建、签名、发布不落在本机 |
| 2026-10-30 | 更新入口直接改 `update-coordinator` 状态机，复用官方 UI | 用户明确不要临时方案；两套更新界面（原生 dialog）后期还要合并，等于白做 |
| 2026-10-30 | 命名一次对齐：`productName` 驱动 `/opt`，`desktopName` 驱动 desktop 文件 | 避免 afterPack 改名这类二次加工；`/opt` 与 desktop 名各有唯一来源 |
| 2026-10-30 | rpm 签名，首装一次性导入公钥，helper 自动 import | 完整性不能降级；helper 里的 import 让更新链对用户仍是「一次授权」 |
| 2026-10-30 | 关闭到托盘与单实例不写补丁 | 上游 `main.ts:1173-1188` 与 `single-instance.ts` 已有，重复实现只会增加重放成本 |
