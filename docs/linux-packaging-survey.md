# DSH 客户端 Linux 打包项目调研

- 调研日期：2026-10-30
- 调研对象：GitHub 上把 DeepSeek Harness 桌面客户端（官方 `deepseek-ai/deepseek-harness` 的 `apps/desktop`，以及社区客户端）打包到 Linux 的项目
- 接口版本基准：上游最新 release `v0.2.2-alpha.2`（2026-10-28，取自 releases.atom）
- 方法：只读。GitHub HTML 页面 + raw/镜像读取文件；未 clone 大仓库、未构建、未调用 api.github.com。所有结论以文件路径/行号为据；读不到的一律标「未核实」
- 结论口径：九个真正打包官方 `apps/desktop`，第十个打的是社区客户端（`dataelement/dsh-desktop`），因它是 AUR 路线唯一成熟样本，单列并标注。另有四个自研壳放附录

## 0. 摘要

1. **主流路线是「官方源码 + 补丁系列」**（ffyfox、JamesYasR、zhsj、boyunxi、TommyFang、jkzero87），其次是「上游整仓 fork」（Zhou、coderirse），非常规路线是「macOS dmg 载荷重打包」（macOS-Terminal）与「自研壳 + 官方 npm 运行时」（附录）。
2. **十个里只有五个产出过 rpm**：ffyfox、JamesYasR、TommyFang、macOS-Terminal、coderirse；其中走官方打包流水线（electron-builder 的 `rpm` 目标 → fpm → rpmbuild）的是 ffyfox 与 coderirse。
3. **平台准入补丁是最小公共集**：target 白名单、`package-target.ts` 的 linux 分支、放宽 `--unsigned`。改的是同一批文件。
4. **真 Node 与 asar 是一对**：要么 `asar: false`，要么 `asar: true + asarUnpack`。上游 Host 跑在 primary-runtime 的真 Node 上，真 Node 读不了 asar。
5. **自启（R3）十个里零实现**——这是空白区，也没有可以直接抄的代码。
6. **更新策略两极**：多数在 Linux 上禁用 electron-updater（正确），TommyFang 自建 Ed25519 feed（与「更新交给 dnf」相悖）。**给 RPM 包嵌 feed 是负资产**：能检查、装不上。
7. **签名几乎全线裸奔**：没有一个项目对 rpm/deb 做 GPG 签名；最接近的是 kamanager2012 的 keyless cosign（只签资产，不签包）。
8. **版本治理三型**：手改 PKGBUILD（会腐化）、日更 fork（冲突成本高）、`upstream-ceiling` + CI 探测（最省）。本项目选的「固定 commit + 每周探测 tag」介于前两者与第三者之间，方向正确，但需补「拒绝腐化」的断言。

## 1. 总表

| # | 项目 | 路线 | 上游钉法 | 产物 | 托盘 | 自启 | 关窗 | 更新 |
|---|---|---|---|---|---|---|---|---|
| 1 | ffyfox/dsh-desktop-linux | 源码 + 16 补丁 | tag + commit | AppImage/deb/**rpm**/Arch | ✓ | ✗ | 隐藏 | 禁用 |
| 2 | JamesYasR/dsh-desktop-linux | 源码 + 19 补丁 | tag + commit + 20 个 sha256 | AUR(`/opt`)、rpm | ✓ | ✗ | 隐藏 | feed 默认关 |
| 3 | zhsj/dsh-desk-flatpak | 源码 + 7 commit | tag + commit | Flatpak | ✓ | ✗ | 隐藏 | 菜单移除 |
| 4 | boyunxi/dsh-linux-packages | 源码、零补丁 | 只写在 README | **deb only** | ✗ | ✗ | — | feed 指向 `example.invalid` |
| 5 | TommyFang2077/dsh-linux-desktop | 源码 + 4116 行大补丁 | commit + tag + 版本三处比对 | deb/rpm **引导包** | ✓ | ✗ | 默认 | Ed25519 feed |
| 6 | jkzero87/dsh-desktop-linux | 上游快照 | 无锁 | AppImage | ✗ | ✗ | **即退** | 零 |
| 7 | macOS-Terminal/deepseek-harness-desktop-linux | **dmg 载荷重打包** | 硬编码 VER | deb/**rpm**/pacman/AppImage | ✓ | ✗ | — | 无 |
| 8 | Zhou-Yujing114514/deepseek-harness-linux | **上游整仓 fork** | 日更同步 | AppImage/deb/tar.gz | ✗ | ✗ | 隐藏 | AppImage 专用 |
| 9 | coderirse/deepseek_harness_linux | 快照 + 3 处改 | 无锁 | AppImage/deb/**rpm** | ✗ | ✗ | — | 无 |
| 10 | xy-arch-git/dsh-desktop-linux | 社区客户端 + AUR | `upstream-ceiling.txt` | tar.zst → AUR | ✗ | ✗ | 即退 | 无 |

注：第 10 项打包对象是社区客户端 `dataelement/dsh-desktop`，不是官方 `apps/desktop`。

## 2. 分项目

### 2.1 ffyfox/dsh-desktop-linux（33★，2026-10-29，仍更）

本地 `.ref/dsh-desktop-linux` 即此仓库（origin 见 `.git/config`，停在 2d52dac / v0.2.2alpha2）。

- 定性：把上游官方打包流水线（`build:official → release:pack → prepare:* → package`）教成认识 `linux-x64`，不打自研壳。
- 补丁：16 个（0001–0018，0014/0015 作废空号），相对 `_tag='dsh-v0.2.2-alpha.2'` / `_commit='f3803c96974ad4a94195fb97e5c637e9c2a3afe3'`。
  - 0001 加 linux-x64 target；0003 改 `apps/desktop/scripts/electron-builder-config.mjs`：`executableName: 'deepseek-harness'`、`desktopName: 'deepseek-harness'`、`asar: platform !== 'linux'`、`rpm: { packageName: 'deepseek-harness' }`；0008 让 Host 走 primary-runtime 的真 Node；0013 Linux 托盘；0018 glass 模式。
- 构建：`build.sh --dir|--appimage|--deb|--rpm|--all` + `scripts/fetch-upstream.sh`（浅克隆 `_tag`）+ `scripts/apply-patches.sh`。
- 布局：`/opt/deepseek-harness-desktop` + `/usr/bin/deepseek-harness` 符号链接 + `/etc/apparmor.d/deepseek-harness`；`dsh-desktop-linux.install` 用 `unshare --user` 探测决定 chrome-sandbox 4755/0755；`conflicts=('deepseek-harness-desktop')`。
- 产物：`upstream/apps/desktop/.desktop-build/targets/linux-x64/unsigned-artifacts/`；linux-unpacked 约 1.1G，rpm 约 242MB。
- CI：`.github/workflows/build.yml` 单 job 出三种格式，Node 24，`DSH_TELEMETRY_DISABLED=1`，timeout 180min。
- 价值：**本项目最直接的基线**——已经能出 rpm，补丁边界清晰。

### 2.2 JamesYasR/dsh-desktop-linux（0★，2026-10-29）

同一作者（`PKGBUILD` 头部 `Maintainer: ffyfox`）的 AUR 向兄弟仓库，质量最高。

- 钉法：`pkgver=0.2.1alpha4` / `_tag='dsh-v0.2.1-alpha.4'` / `_commit='86a402200d95fecef4529d969836f1fe13c6cb0d'` + 20 条 `sha256sums`。
- 19 个补丁分四刀：
  - 0001–0007 平台准入；0008–0010 真 Node（新增 `DesktopNodeRuntime`，`ELECTRON_RUN_AS_NODE` 只在真 Electron 下设置）、`desktopPlatformEmbedsPolicy()` 让 Linux 不嵌强制更新策略；0011–0012 包元数据 + 非 git 源码构建（`readDesktopBuildCommit()` 接受 `DSH_DESKTOP_BUILD_COMMIT`）；0013 托盘；0015 Wayland 浮层 `did-finish-load` 兜底；0016/0017 更新 feed（构建期 + 运行期）；0018 标题栏；0019 未打包布局下 CLI 找 runtime；0020 自动检查开关 + 回滚。
- 关键行：`patches/0003-*.patch` 第 48 行 `- asar: true` → `+ asar: resolvedPlatform !== 'linux'`（注释：独立 Node 读不了 ASAR）。
- 标题栏：`0018` 新增 `src/linux-window.ts` + `src/linux-caption.ts`，`DSH_DESKTOP_LINUX_WINDOW_CHROME`（`caption` 默认 / `native` / `rounded`），`overlayControls = win32 || (linux && chrome==='caption')`，`titleBarStyle:'hidden'` + `setTitleBarOverlay()`；实测非客户区 110px→42px。
- 补丁工程：`git diff` 逐文件生成，每个补丁一棵隔离树（避免共用文件 hunk 串味）；`scripts/apply-patches.sh` 用 `git apply`，PKGBUILD `prepare()` 用 `patch -Np1`，CI 断言两棵树逐字节一致。二进制托盘 PNG 不进补丁，走 `assets/tray-linux.png` 旁挂。
- 布局：`/opt/deepseek-harness-desktop/` + `/usr/bin/deepseek-harness` + `hicolor/scalable/apps/deepseek-harness.svg`（0003 特意指定 SVG：单 PNG 会被塞进 `hicolor/1024x1024/apps`，部分发行版 `index.theme` 不声明该目录）+ `/etc/apparmor.d/deepseek-harness`。chrome-sandbox 的 4755 由 `.install` 的 `_fix_chrome_sandbox()` 决定。
- 依赖：gtk3、nss、libnotify、libxss、libxtst、xdg-utils、at-spi2-core、libsecret、alsa-lib、dbus、`libxcrypt-compat`、`libdbusmenu-glib`（dlopen，SNI 托盘菜单必需，`ldd`/namcap 看不见）。
- 风险：PKGBUILD 停在 alpha.4，release 已到 `0.2.1-rc.4`，**基线已脱节**——「手工重放补丁」的运维债，正好印证 PLAN 的「上游升版需重放补丁」。

### 2.3 zhsj/dsh-desk-flatpak（2★，2026-10-28）

- manifest `com.deepseek.harness.yml` 钉 `tag dsh-v0.2.2-alpha.2` / `commit f3803c96974ad4a94195fb97e5c637e9c2a3afe3`；构建命令 `pnpm --filter @deepseek-ai/dsh-desktop run package:dir`。
- runtime `org.freedesktop.Platform|Sdk 26.08` + base `org.electronjs.Electron2.BaseApp 26.08` + sdk-ext `node24`；构建期装 pnpm 11.28.5。
- 补丁：7 个 commit 用 `git format-patch --stdout master..linux-flatpak` 一条命令重生成（含新文件 `apps/desktop/scripts/linux-hotfix-libreoffice-kit.ts`）；`update_release.py` 用 `git tag --sort=-creatordate dsh-v* --merged` 自动跟 tag/commit。
- 产物装 `/app`，launcher `exec zypak-wrapper /app/main/deepseek-harness`，`DSH_HOME="${XDG_DATA_HOME}/dsh"`；desktop `StartupWMClass=com.deepseek.harness`、`MimeType=x-scheme-handler/dsh`；图标 `ffmpeg` 生成 hicolor 48/64/128/256/512，无 scalable。
- 两处硬伤：`finish-args` 只有 `--socket=wayland`（无 x11/fallback-x11，X11 会话跑不起来）；安装命令 `flatpak remote-add --user --no-gpg-verify`（信任只剩 TLS）。
- 可取：7 commit 补丁集 + `format-patch` 重生成；tag/commit 双钉；**zypak 证明不靠 setuid chrome-sandbox 也能跑**。

### 2.4 boyunxi/dsh-linux-packages（0★，2026-10-03，1 commit）

- 最小公式：`pnpm --filter @deepseek-ai/dsh-desktop run prepare:linux` 后 `electron-builder --linux deb --x64 --publish never`。
- 装 `/opt/DeepSeek Harness/`（productName 带空格），313 MiB，~1.17 GiB 解包；`postinst` 按 userns 探测定 chrome-sandbox 0755/4755。
- 两个真坑：必须 `set -a; . ./.env.linux`（否则 `DSH_DESKTOP_APP_ID` 缺失）；必须清 `ELECTRON_RUN_AS_NODE` 与 `CODEBUDDY_*`。
- 回答「300MB 从哪来」：没有特殊手法，就是把整棵 Electron 44 树打进 `/opt`。
- 缺陷：Release 资产 404（313 MiB deb 没挂上）；deb 内 `resources/app-update.yml` 指向 `example.invalid`；零锁、零 patch、零 CI。

### 2.5 TommyFang2077/dsh-linux-desktop（5★，2026-10-25）

- 唯一「引导包」路线：deb/rpm 里只放 `/usr/share/dsh-workbench/{desktop.tar.gz,node,install-user.mjs}` + `/usr/bin/dsh-workbench` 启动器；首启把真程序装进 `~/Applications/dsh-linux-desktop/versions/<sha256>`，`current` 原子软链。
- 补丁：`patches/linux.patch` 4116 行 / 70+ 文件（托盘、`setApplicationMenu(null)`、禁 protocol client、`win32||linux` 建 DesktopTray）；关窗隐藏无 hunk（上游默认），自启无实现。
- 版本治理最严：`upstream.json` 锁官方 repo/commit/version，`validate_source_lock` 强制 40-hex，checkout 后三处版本比对，不符 raise；CI 用 api.github.com 复核官方 tag→commit→version。
- 更新：Ed25519 签名 feed（`updates.json` → `update-feed/*-follow-latest.json`，公钥 `MCowBQYDK2VwAyEA...`），应用内更新绝不 sudo；deb/rpm 本身不签。
- `/opt` 在其 verify 脚本里被硬禁（出现 `/opt/` 即 raise）；`dpkg-deb -Zgzip -z1`；rpmbuild `_rpmformat 4` / `w1.gzdio`。
- 取舍：解决「rpm 管 /usr vs 程序要写自身」的矛盾，但**让包管理器失去文件所有权**，R5 的「一次授权」也就失去意义；Ed25519 feed 对「更新交给 dnf」是纯负债。

### 2.6 jkzero87/dsh-desktop-linux（1★，2026-10-19）

- 上游 `dsh-v0.2.1-rc.2` 整树快照；Linux 改动以提交折进树里，`patches/` 里 8 个全是 pnpm `patchedDependencies`（无一行 Linux）。
- 平台准入已在上游：`apps/desktop/scripts/package-target.ts:50/83/190`。
- `asar: true` + `asarUnpack`（`electron-builder.config.mjs:79-85`，`node_modules/**`、`sharp`、`libreoffice-kit-*` 全解出来）——比 `asar:false` 更「够用」，但坑会在别的路径复发。
- Linux 不建托盘（`src/main.ts:998` 仍 `process.platform === 'win32'`），因此关窗即退（`:1085-1097`），`window-all-closed` 也 quit。
- 构建必须 `--unsigned`（否则要求 `DOWNLOAD_TEST_ORIGIN` + 32 位 hex `DOWNLOAD_TEST_RELEASE_ID`）；产物只有 AppImage，`publish: null`，零更新。
- 可取：AppArmor 模板 + 「有 profile 走真二进制、无 profile 走 AppRun、`unshare -Ur` 失败才 `--no-sandbox`」的判定顺序；`.desktop` 里 `DSH_TELEMETRY_DISABLED=1`、OTLP 指 `127.0.0.1:9`。

### 2.7 macOS-Terminal/deepseek-harness-desktop-linux（10★，2026-10-25）

- 不打源码：把官方 macOS arm64 dmg（`0.2.1-rc.2`）载荷重打包为 8 个包（x86_64/aarch64 × AppImage/bundled.deb/pkg.tar.zst/rpm，全 zstd）。
- `patches/patch-main.py` 八项：平台白名单、`x-client-platform` 报 `desktop-linux`、注入 `desktopIsPackaged()`（`DSH_DESKTOP_FORCE_PACKAGED`）与 `desktopResourcesRoot()`（`DSH_DESKTOP_RESOURCES_DIR`）、托盘 PNG 回退链 + `win32 || linux`、无托盘则真退出；`patch-fingerprint.py` 按 ELF 符号 `MatchesERKNS2_19ElectronProfileSpecE` 改 V8 指纹。
- 布局：`/usr/lib/deepseek-harness` + `/usr/bin/deepseek-harness` sh wrapper；desktop `StartupWMClass=deepseek-harness`、`MimeType=x-scheme-handler/dsh`；chrome-sandbox 4755 写三处（deb postinst、rpm `%exclude`+`%attr(4755,root,root)`、pacman `.INSTALL`）。
- **rpm spec 现成配方**：`AutoReqProv: no`、`%global __os_install_post %{nil}`、`__strip`/`__brp_strip` 指向 `/bin/true`、`_binary_payload w19.zstdio`、Requires 全手写、`%post`/`%postun` 跑 `update-desktop-database` + `gtk-update-icon-cache`。
- 缺陷：无 CI、无签名（仅 SHA256SUMS）、版本硬编码、固定端口 19387 无单实例；`build-packages.sh:27` 的 `RPMVER` 与 `:294` 重复拼 `${RPMARCH}`，产物名成 `...x86_64.x86_64.rpm`。

### 2.8 Zhou-Yujing114514/deepseek-harness-linux（158★，2026-10-27，活跃）

- 完整 fork 上游 monorepo（22,444 commits）。`sync-upstream.yml` cron `17 2 * * *` 日更合并，按 `OURS_PATHS` 白名单保留己方（`apps/desktop/scripts/`、`.env.linux.example`、`README.md`、`package.json`、`.github/workflows/desktop-linux.yml`、`release-attach.yml`、`.github/actions/prepare-linux-env/`、`smoke-linux-appimage/`、`README*.md`），只开 PR。
- 构建 `pnpm --dir apps/desktop run package:linux:x64` → `tsx scripts/package-target.ts linux-x64`，要求同架构 Linux 机器；Node 24/pnpm 11.28.5/libfuse2；asar 默认 true，随包 Node 在 `resources/runtime/primary-runtime/dependencies/node/bin/`。
- 产物 `['AppImage','deb','tar.gz']`，`executableName deepseek-harness`，无 packageName/图标/%post/depends；**不产 rpm**。
- 托盘只 `src/main.ts:992` 的 `win32` 分支；关窗隐藏 `src/main.ts:1079-1086` 上游原生；单实例 `single-instance.ts` 跨平台；无自启。
- AppImage 用 electron-updater generic（`https://sswwgzs.cn/dsh/`，nightly），未签名；CI `desktop-linux.yml` 385 行，x64→ubuntu-24.04、arm64→ubuntu-24.04-arm，`smoke-linux-appimage` 真启动冒烟。
- 价值：同步机制可参考（日更 fork 的冲突成本极高，不建议本项目采用）。

### 2.9 coderirse/deepseek_harness_linux（0★，2026-10-04）

- 上游 0.2.1-alpha.1 的单次快照导入（8 commits），无同步、无 Linux CI。
- 三处改动：`apps/desktop/scripts/electron-builder-config.mjs` 的 linux 段（L243-257）与 deb/rpm 段（L259-260）；新增 `apps/desktop/scripts/linux-app-update-config.mjs`；`desktop-toolchain-preflight.ts` 加 rpmbuild 探测（报错文案 `the rpm target needs the rpmbuild executable`）。
- **唯一用 electron-builder 的 `rpm` 目标真出过 rpm 的项目**（v0.2.1-alpha.1 的 `-linux-x86_64.rpm`）。
- 关键手法：`deb/rpm.packageName = 'deepseek-harness'`（注释：productName 带空格非法、会破坏 fpm 生成的 spec）、`syncDesktopName: true`、`mimeTypes: ['x-scheme-handler/dsh']`、maintainer 必填。
- README 明说 deb/rpm 无应用内更新，更新归包管理器。

### 2.10 xy-arch-git/dsh-desktop-linux（3★，2026-10-27）——非官方客户端

- 打的是社区客户端 `dataelement/dsh-desktop`（0.12.1），不是官方 `apps/desktop`；全仓 20 个文件，纯打包流水线。
- 自产 tar.zst（约 194MB）+ `.sha256`；AUR `aur/dsh-desktop-bin/PKGBUILD` 只做下载/解包/`/opt/dsh-desktop` + `/usr/bin` 符号链接 + desktop + 约 30 条依赖 + optdepends `libappindicator-gtk3`；无 `.install`、chrome-sandbox 只 0755。
- `upstream-ceiling.txt` 唯一非注释行 `0.12.1`，注释写明理由：0.11.0 起上游改用 Electron-as-Node，Linux 上 sharp 段错误（electron/electron#46323）。`auto-release.yml` 用 `git ls-remote --tags | sort -V | tail -1` 探测最新，超上限 skip 并开 issue。
- 售后：本地脚本 = CI 脚本（`build-release.sh` 508 行），天然适配 `%build` 段；会话格式闸门（`SESSION_FORMAT_VERSION` 与上一 Release 比对）防迁移断链。
- 不可照搬：依赖字符串锚点改写上游构建脚本，上游一改就断；无 postinst；`.SRCINFO` 与 PKGBUILD 脱节。

## 3. 横向结论

1. **平台准入补丁是最小公共集**：target 白名单 + `package-target.ts` 的 linux 分支 + 放宽 `--unsigned`，ffyfox/JamesYasR/coderirse 改的是同一批文件。
2. **真 Node 与 asar 是一对**：`asar:false`（ffyfox、JamesYasR）或 `asar:true + asarUnpack`（jkzero87、Zhou）。上游 Host 用 primary-runtime 的真 Node，真 Node 读不了 asar——不是口味问题。
3. **托盘补丁只有一行门禁**（`platform === 'win32'` → `|| 'linux'`），但 GNOME 侧还要 `gnome-shell-extension-appindicator` + `libdbusmenu-glib`（dlopen，`ldd`/namcap 看不见，缺了是「图标在、菜单空」）。真开托盘的只有 1、2、3、5、7。
4. **自启（R3）零实现**：十个项目里没有一处 `setLoginItemSettings` / autostart 写文件。这是空白区，也是差异化点。
5. **关窗语义**：上游本来就是 `close → hide`，「有托盘」是前提；没托盘的（6、8、10）要么关窗即退，要么窗口隐藏后叫不回来。
6. **更新**：多数选择「不做」，且分两类——包管理器派（1、2、9 在 Linux 禁用 electron-updater）与自签 feed 派（2 的 AppImage、5 的 Ed25519）。**RPM 包里嵌 feed 是负资产**：能检查、装不上（`ERR_UPDATER_OLD_FILE_NOT_FOUND`），且绕过 dnf。
7. **签名**：GPG 签 rpm 的实际一个都没有；最接近的是 kamanager2012 的 keyless cosign（只签资产）。PLAN 的「GPG 私钥进 Actions secrets」有区分度。
8. **版本治理三型**：手改 PKGBUILD（1、2，会腐化）、日更 fork（8，冲突成本高）、`upstream-ceiling` + CI 探测（10，最省）。

## 4. 对本项目的取舍

- **基线抄 1，补丁组织抄 2，rpm 目标抄 9，spec 细节抄 7**：
  - ffyfox 的流水线已经能出 rpm；
  - JamesYasR 的「四刀分层 + 每补丁隔离树 + 双路应用断言」解决 PLAN 最担心的「上游升版补丁重放」；
  - coderirse 证明 `packageName` 必须无空格、`syncDesktopName` 必须开；
  - macOS-Terminal 的 `__os_install_post %{nil}` + 手写 Requires 是 Electron 包的标准解法（别让 rpmbuild strip 那堆 .so）。
- **布局选 `/opt/deepseek-harness-desktop` + `/usr/bin` 符号链接**，与 1、2 一致；不采纳 TommyFang 的 HOME 引导包——它让 dnf 失去文件所有权，R5 的「一次授权」就没意义了。
- **R3 自启**：`%post` 写 `/etc/xdg/autostart` 更可控，且能配 `--hidden`；不要用 westanke 的 `setLoginItemSettings`（Electron API 在 Linux 的落地文件名未核实）。
- **R5 坚决不嵌 feed**：照 2 的 PKGBUILD，只写 `DSH_DESKTOP_APP_ID`、不设 `DSH_DESKTOP_LINUX_UPDATE_ORIGIN`；检查更新只读 `version.json`，安装只走 `pkexec` + `dnf5`。
- **降级策略**：若哪天决定「上游不值得跟」，`upstream-ceiling.txt` + 每天探测 tag、超限自动开 issue 可直接拿来当 CI 策略。

## 5. 附录：不是官方客户端、但值得看一眼

| 仓库 | 定性 | 可借 | 不可照搬 |
|---|---|---|---|
| kamanager2012/dsh-community | 官方 npm 运行时 + 自写 Electron 壳 | `shell-policy.ts` 把「关窗/托盘」抽成纯函数 + `hideToTray` + 托盘不可用即退出的降级；pin + lockfile + CI 三处一致；keyless cosign | AppImage 不声明依赖、不设 setuid；运行时 tar 首启解包 |
| nicolodon/dsh-linux | anywhere-labs 壳的 Linux 移植 | `vendor/` 241 个 tarball + sha256 manifest + `--check`（官方 runtime 原样钉版）；userns→4755/0755 | 528MB、整棵 `node_modules` 解包；更新打 `dshdesktop.cn` 且不校验哈希；无 rpm |
| westanke/dsh-desktop-deepin | 自研壳（Deepin） | `src/main.js:1794-1802` close→hide；`:2051-2056` `setLoginItemSettings`；postinst「秒级返回 + 降权后台预热」 | 首启下载 180MB Electron 与「菜单即用」冲突；仅 deb |
| RidgeBridgeStudios/dsh-desktop-deb-workshop | 官方 CLI + 系统 Node 的薄壳 | polkit `allow_active=yes` 升级助手、AppArmor `userns` profile（与 R5 同构） | 用系统 Node 跑 CLI，不是客户端打包 |
| KaffuAlcaid/dsh-desktop-unofficial、koompi/dsh-desktop、Quan-Robin/DSH-desktop-for-Linux、zsyu9779/dsh-desktop | 自研壳 / Tauri / Wails | 仅作「不要重做客户端」的反例 | 全部 |

## 6. 未核实项

- 各项目是否提供开机自启：1–10 均未在 main 入口发现 `setLoginItemSettings`/`openAtLogin`/autostart 写入，但均未做全库正则。
- electron-builder 生成的 rpm 内 spec 全文：未拆包比对，仅依据 fpm `templates/rpm.erb` 与 macOS-Terminal 的手写 spec 推断。
- jkzero87 的升级/rebase 流程；mtaech/dsh-linux-patch 的内容（未调研）。
- zhsj AppImage/flatpak 内部布局；nicolodon AppImage 内部布局。
- 星标与提交时间为调研时刻（2026-10-30 02:17 +08:00）快照，会变。

## 7. 参考坐标

- 上游：`deepseek-ai/deepseek-harness`，`apps/desktop`，release `v0.2.2-alpha.2`（2026-10-28）
- 本地参考：`.ref/dsh-desktop-linux`（= ffyfox，2d52dac / v0.2.2alpha2）
- 本机工具链：Fedora 44、dnf5 5.4.6、node v26.8.1、pnpm 11.25.0、git 2.56.0、rpm 6.0.2；`rpmbuild`/`createrepo_c`/`fpm` 未装
