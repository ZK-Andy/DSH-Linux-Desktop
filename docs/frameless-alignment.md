# Linux 无边框架构对齐计划

参考主对象：ZCode 3.17.1（`zai-org/ZCode`，本地 `/mnt/work/DSH-Linux-Desktop/.ref/zcode`）。
基线：上游 `deepseek-ai/deepseek-harness` 的 `apps/desktop`。规则见 `AGENTS.md` §6：**禁止自创；对齐 = 架构对齐**。

## 0. 决策与有意偏离

| 决定 | 内容 | 理由 |
| --- | --- | --- |
| 窗口不透明 | ZCode 用 `transparent: true` + 不透明壳露四角；我们用不透明窗口，圆角以内层壳的底色填平 | 用户确认透明窗口的逐帧 alpha 合成耗尽内存，且不做玻璃模式（m03759） |
| 不做玻璃 | 不保留任何可被环境变量打开的透明路径 | m03759 |
| 参考优先级 | 窗口/页面结构对 ZCode；托盘、更新、sharp 等产品行为对 PLAN | 各取所长，不混用 |

## 1. 对齐项清单

状态：`[ ]` 未做，`[x]` 已做，`[~]` 有意偏离，`[?]` 待拍板。

### A. 窗口层

| # | 项 | ZCode 出处 | 我们现状 | 状态 |
| --- | --- | --- | --- | --- |
| A1 | 最小尺寸 480×640 | `desktopWindowSize.ts:6-7` | 520×600 | `[x]` |
| A2 | 窗口尺寸/最大化持久化 | `desktopWindowSize.ts:17-40`、`desktopWindowChrome.ts:644-646` | `src/settings.ts` 的 `desktopWindowSize` + `saveDesktopWindowSize`；`main.ts` 的 `restoredWindowSize()`/`attachWindowSizePersistence()` | `[x]` A2-1：普通尺寸 + 最大化标志，`getNormalBounds()` 落盘、主屏工作区裁剪 |
| A3 | Linux `autoHideMenuBar` | `desktopWindowChrome.ts:617` | 只 `setMenuBarVisibility(false)` | `[x]` |
| A4 | 窗口 `icon` | `desktopWindowChrome.ts:614` | `main.ts` 的 `framelessWindowIcon()`；`electron-builder-config.mjs` 的 linux `extraResources` 加 `app-icon.png` | `[x]` A4-1：打包态取 `process.resourcesPath/app-icon.png`，dev 取 `resources/icons-linux/256x256.png` |
| A5 | 启动恢复最大化 | `desktopWindowChrome.ts:644-646` | `createWindow` 里 `if (primary && size.maximized) window.maximize()` | `[x]` 随 A2 一起做 |
| A6 | zoom 档位恢复 | `desktopWindowChrome.ts:629/681` | 无 | `[ ]` A6-2 不做（用户拍板） |
| A7 | 外链处理 | `desktopWindowChrome.ts:635-643` | http/https 交系统浏览器，其余 deny | `[~]` 产品行为不同（无内嵌浏览器） |
| A8 | 窗口创建即可见 | `desktopWindowChrome.ts:615`（不传 `show`） | 原先 `show=false`，等 `navigateMain` 完才 `show()` | `[x]` `createWindow(appPreload, true, true)`，frameless 加 `backgroundColor: chromeFallbackFill()` 防白闪；加载由启动壳遮挡 |

### B. 页面壳与几何

| # | 项 | ZCode 出处 | 我们现状 | 状态 |
| --- | --- | --- | --- | --- |
| B1 | 壳 `rounded-xl border border-border` | `WorkspaceShellWindowChrome.ts:40` | 无 | `[x]` |
| B2 | 内容区 `pr-1 pb-1`（4px） | `WorkspaceShellLayout.tsx:2553-2556` | 无 | `[x]` |
| B3 | 顶部 4px 拖拽条 | `WorkspaceShellLayout.tsx:2559` | 无 | `[x]` |
| B4 | resize 命中 16px | `workspaceShellWindowChrome.ts:30` | 无 | `[x]` |
| B5 | 全屏不特判 | 无 fullscreen CSS | 自创 `html[data-fullscreen]` 规则 | `[x]` |

### C. 侧栏顶部

| # | 项 | ZCode 出处 | 我们现状 | 状态 |
| --- | --- | --- | --- | --- |
| C1 | 品牌与折叠按钮同一行 | `DesktopTopOverlay.tsx:117-135`、`project-sidebar/index.tsx:226` | 两行（macOS 让位条 + logoRow） | `[x]` |
| C2 | 侧栏折叠宽 4px 内缩 | `WorkspaceShellLayout.tsx:452` | 0（linuxGlass 分支） | `[x]` |
| C3 | 顶部 48px 拖拽行 | `project-sidebar/index.tsx:226` | 复用上游 `data-window-drag` | `[x]` |

### D. 窗口按钮与拖拽

| # | 项 | ZCode 出处 | 我们现状 | 状态 |
| --- | --- | --- | --- | --- |
| D1 | 按钮在渲染层组件、按命令通道 | `DesktopWindowControls.tsx:56-66`、`desktopCommandHandlers.ts:524-527` | preload 注入 + 自建 IPC | `[x]` |
| D2 | 按钮尺寸/位置随面板 | `h-12`、面板右上角 | 28×28；会话头 corner 座位，右面板打开时由面板标签条末端 `data-dockkit-strip-chrome` 接管 | `[x]` |
| D3 | 拖拽按行显式声明 | 各 48px 顶行 `[app-region:drag]` | 全局选择器 | `[x]` |
| D4 | 控件让位 `padding-right: 112px` | 无（ZCode 控件在布局里） | 仅在浮动（overlay）座位保留让位 | `[x]` |

### E. 启动与页面

| # | 项 | ZCode 出处 | 我们现状 | 状态 |
| --- | --- | --- | --- | --- |
| E1 | 启动淡入 0.16s | `renderer/index.html` | `apps/web/index.html`：`#root` 0.16s 淡入、`#loading` 0.16s 淡出 | `[x]` 只在 `dsh-workspace-ready`（`AppFrame` 首帧后双 rAF 派发）到达后触发，8s 兜底 |
| E2 | logo pop 0.72s | `renderer/index.html` | 无 | `[x]` pop 0.72s 后接 `startup-logo-breathe` 1.5s 循环（对齐 ZCode SMIL 的 1;0.3;1），壳不再按动画时长收场 |
| E3 | 页面加载路径 | `loadFile(index.html)` | `serveWebDocument` 注入 | `[~]` 改 loadFile 要动 Web 打包 |

### F. 自创清理

| # | 项 | 内容 | 状态 |
| --- | --- | --- | --- |
| F1 | 品牌塞进 topStrip | 自创放法，随 C1 重做 | `[x]` |
| F2 | 全屏隐藏控件 | 自创规则，随 B5 删除 | `[x]` |
| F3 | `padding-right: 112px` | 自创让位，随 D1 删除 | `[ ]` |

## 2. 执行顺序

1. **P1 窗口层**：A1、A3、B5（F2 一并删除）。不含 F3——控件仍是 preload 覆盖层，让位要等 D1。
2. **P2 壳与几何**：B1–B4，在客户端 `ui-layout` 里按 ZCode 的层次落地（壳不透明铺满、内容 4px、圆角/边框在壳上、resize 16px）。
3. **P3 侧栏**：C1–C3、F1（取消 macOS 让位条在 Linux 的使用，品牌与开关同一行；折叠宽 4px）。
4. **P4 控件与拖拽**：D1–D4、F3（按钮进渲染层组件与命令通道，拖拽按行声明）。
5. **P5 启动**：E1–E2。
6. **P6 复查**：逐项勾选；esbuild/tsc 能跑则跑；重生成补丁并重放；等许可后一次 CI。

## 3. 验证方式

- 每阶段：改动文件 esbuild 语法检查；客户端改动尽量 `tsc -b`（本机内存不足时记录为未跑）。
- 全部完成后：重新生成补丁、干净 tag 重放、等许可后一次 CI（构建 + 静态验收 + 冒烟）。
- 不在本机跑全量构建（内存风险）。

## 4. 待拍板

1. ~~A2/A5/A6 依赖设置存储~~：A2-1 全量持久化 + A5 一起做；A6-2 不做。
2. ~~A4 窗口 icon~~：A4-1 传 icon，打进 linux 的 extraResources。
