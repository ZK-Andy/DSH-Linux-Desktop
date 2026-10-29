#!/usr/bin/env bash
# 静态验收：只看 rpm 里的东西，不启动应用（活体验收是 scripts/smoke-install-rpm.sh 的事）。
#
#   ./scripts/verify.sh dist/dsh-desktop-*.rpm
#   ./scripts/verify.sh                 # 自动找 dist/*.rpm，其次找构建产物目录
#
# 检查项对应 PLAN §3.7（身份与安装布局）与 R1/R2 的静态前提：包名、版本、依赖、安装路径、
# desktop 入口、托盘图标、asar 与 sharp 的 unpack 布局、sandbox 处理脚本。
# 任何一项不过都计数并在最后汇总退出码；逐项写清为什么这么判。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG_FILE="$ROOT/upstream-tag"

rpm="${1:-}"
if [[ -z "$rpm" ]]; then
  rpm="$(find "$ROOT/dist" -maxdepth 1 -name '*.rpm' 2>/dev/null | head -1)"
fi
if [[ -z "$rpm" ]]; then
  rpm="$(find "$ROOT/upstream/apps/desktop/.desktop-build/targets/linux-x64" -name '*.rpm' 2>/dev/null | head -1)"
fi
[[ -f "$rpm" ]] || { echo "找不到 rpm；传一个路径进来" >&2; exit 1; }

command -v rpm >/dev/null || { echo "需要 rpm 命令（rpm -qip / rpm2cpio）" >&2; exit 1; }
command -v cpio >/dev/null || { echo "需要 cpio（用来从 rpm 里取单个文件）" >&2; exit 1; }

fail=0
pass=0
check() { # check <描述> <命令...>
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  ok   %s\n' "$what"
  else
    fail=$((fail+1)); printf '  FAIL %s\n' "$what"
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 从包体里读一个文件到 stdout；参数是 rpm 里的绝对路径（/usr/share/...）。
# cpio 归档里的名字不带前导斜杠，所以匹配前先剥掉。
rpm_cat() { local path="${1#/}"; rpm2cpio "$rpm" | ( cd "$tmp" && cpio -i --to-stdout --quiet "$path" ); }

echo "==> rpm: $rpm"

# --- 身份 ---
name="$(rpm -qp --qf '%{NAME}' "$rpm" 2>/dev/null)"
version="$(rpm -qp --qf '%{VERSION}' "$rpm" 2>/dev/null)"
arch="$(rpm -qp --qf '%{ARCH}' "$rpm" 2>/dev/null)"
check "包名是 dsh-desktop（不是上游的 deepseek-harness）" test "$name" = "dsh-desktop"
check "架构是 x86_64（本项目只发 x86_64）" test "$arch" = "x86_64"
# unsigned 构建带 -unsigned 后缀（desktopArtifactOutput 决定），发布签名后才去掉。
base="$(basename "$rpm")"
check "文件名是 dsh-desktop-<version>[-unsigned]-x86_64.rpm" \
  bash -c "[[ \"$base\" == \"dsh-desktop-${version//\~/-}\"-x86_64.rpm || \"$base\" == \"dsh-desktop-${version//\~/-}-unsigned-x86_64.rpm\" ]]"

if [[ -f "$TAG_FILE" ]]; then
  tag="$(head -n1 "$TAG_FILE" | tr -d '[:space:]')"
  # rpm 的 Version 不能带 '-'：electron-builder 把 0.2.2-alpha.2 映射成 0.2.2~alpha.2，
  # 这样 alpha/rc 在 dnf 的版本比较里排在正式版之前。
  want="${tag#dsh-v}"; want="${want//-/\~}"
  check "版本由 upstream-tag 推出（$tag → $want）" test "$version" = "$want"
fi

# --- 依赖：显式声明，含两个 dlopen-only 的库（ldd 看不见）---
requires="$(rpm -qp --requires "$rpm" 2>/dev/null)"
for dep in gtk3 nss libnotify libXScrnSaver xdg-utils at-spi2-core libsecret libdbusmenu; do
  check "Requires 含 $dep" grep -qx "$dep" <<<"$requires"
done
check "Requires 含 libXtst 备选表达式" grep -q 'libXtst' <<<"$requires"
check "Requires 含 libuuid 备选表达式" grep -q 'libuuid' <<<"$requires"
check "没有把上游包名当依赖（deepseek-harness）" bash -c "! grep -qx 'deepseek-harness' <<<'$requires'"

# --- 安装布局 ---
files="$(rpm -qpl "$rpm" 2>/dev/null)"
check "主程序在 /opt/deepseek-harness-desktop/deepseek-harness" \
  grep -qx '/opt/deepseek-harness-desktop/deepseek-harness' <<<"$files"
check "desktop 文件是 dsh-desktop.desktop（desktopName + syncDesktopName）" \
  grep -qx '/usr/share/applications/dsh-desktop.desktop' <<<"$files"
check "图标落在 hicolor" \
  grep -q '^/usr/share/icons/hicolor/.*/apps/' <<<"$files"
check "托盘 PNG 在 resources 下（0013 的 extraResources）" \
  grep -qx '/opt/deepseek-harness-desktop/resources/tray-linux.png' <<<"$files"
check "sharp worker 在 resources 下（0021 的 extraResources）" \
  grep -qx '/opt/deepseek-harness-desktop/resources/sharp-worker.cjs' <<<"$files"
check "asar 保持开启（PLAN §3.6）" \
  grep -qx '/opt/deepseek-harness-desktop/resources/app.asar' <<<"$files"
# dsh 工作区在包里落成 resources/app.asar 的 dsh/ 子树，unpack 出来的文件同样带 dsh/。
check "sharp 被 unpack 到 app.asar.unpacked 的 dsh 子树" \
  grep -qE '^/opt/deepseek-harness-desktop/resources/app\.asar\.unpacked/.*/node_modules/sharp/' <<<"$files"
check "libvips（@img）也被 unpack" \
  grep -qE '^/opt/deepseek-harness-desktop/resources/app\.asar\.unpacked/.*/node_modules/@img/' <<<"$files"
check "chrome-sandbox 存在" \
  grep -qx '/opt/deepseek-harness-desktop/chrome-sandbox' <<<"$files"

# --- desktop 入口内容 ---
desktop="$(rpm_cat /usr/share/applications/dsh-desktop.desktop 2>/dev/null)"
check "desktop Name 是菜单里显示的 DeepSeek Harness" grep -qx 'Name=DeepSeek Harness' <<<"$desktop"
check "desktop Exec 指向安装前缀" grep -q '^Exec=/opt/deepseek-harness-desktop/deepseek-harness %U' <<<"$desktop"
check "desktop 声明 StartupWMClass=dsh-desktop" grep -qx 'StartupWMClass=dsh-desktop' <<<"$desktop"
check "desktop 注册 dsh:// 处理者" grep -qx 'MimeType=x-scheme-handler/dsh;' <<<"$desktop"

# --- 安装脚本：只做 sandbox 与缓存刷新，不写用户目录 ---
post="$(rpm -qp --scripts "$rpm" 2>/dev/null | sed -n '/^postinstall scriptlet/,/^[a-z].* scriptlet/p')"
check "%post 处理 chrome-sandbox" grep -q 'chrome-sandbox' <<<"$post"
check "%post 用 unshare 探测 user namespace 后再决定 4755/0755" grep -q 'unshare --user true' <<<"$post"
check "%post 刷新 desktop 数据库" grep -q 'update-desktop-database' <<<"$post"
check "%post 建 /usr/bin/deepseek-harness 入口" grep -q '/usr/bin/deepseek-harness' <<<"$post"
check "%post 不往用户 home 写东西" bash -c "! grep -q '/home/' <<<'$post'"

echo
printf '==> %d 项通过，%d 项失败\n' "$pass" "$fail"
exit "$((fail > 0))"
