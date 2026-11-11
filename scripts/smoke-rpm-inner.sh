#!/usr/bin/env bash
# 容器内冒烟：装 rpm → 在 Xvfb 里启动 → 确认建出可见窗口 → 截图。
# 由 scripts/smoke-install-rpm.sh 挂到 /smoke-inner.sh 以 root 调用；两阶段自举：
#   阶段一（无 DISPLAY）：装包与 X11/DBus 工具，然后把自己重新放进会话总线 + Xvfb；
#   阶段二（--launch）：启动应用、等窗口、截图、落 app.log。
set -uo pipefail

log() { printf '[rpm-smoke] %s\n' "$*"; }
SHOT_DIR="${SMOKE_SHOT_DIR:-/shots}"
LOG_DIR="${SMOKE_LOG_DIR:-/smokelogs}"
APP=/usr/bin/deepseek-harness
mkdir -p "$SHOT_DIR" "$LOG_DIR"

# ---------- 阶段二：有 DISPLAY，启动并验证 ----------
if [[ "${1:-}" == "--launch" ]]; then
  export DSH_HOME="${DSH_HOME:-/tmp/dsh-home}"
  app_log="$LOG_DIR/app.log"
  # 直接跑包内的二进制：/usr/bin 的入口是 %post 用 update-alternatives/ln 建的，
  # 容器里不一定存在；它在装包断言里单独验。
  APP_BIN=/opt/deepseek-harness-desktop/deepseek-harness
  [ -x "$APP_BIN" ] || { log "缺少 $APP_BIN"; exit 1; }
  "$APP_BIN" --no-sandbox --disable-gpu --disable-dev-shm-usage >"$app_log" 2>&1 &
  app=$!
  trap 'kill "$app" 2>/dev/null || true' EXIT

  window=""
  for _ in $(seq 1 30); do
    sleep 2
    if ! kill -0 "$app" 2>/dev/null; then
      log "app 在出窗口前退出（见 app.log 尾部）"
      tail -50 "$app_log" >&2
      exit 1
    fi
    window=$(xdotool search --onlyvisible --name . 2>/dev/null | head -1 || true)
    [[ -n "$window" ]] && break
  done
  if [[ -z "$window" ]]; then
    log "60 秒内没有可见窗口（见 app.log 尾部）"
    tail -50 "$app_log" >&2
    exit 1
  fi

  title=$(xdotool getwindowname "$window" 2>/dev/null || echo '?')
  class=$(xdotool getwindowclassname "$window" 2>/dev/null || echo '?')
  log "window=$window title=$title class=$class"
  if printf '%s' "$title" | grep -qiE 'unavailable|无法使用|利用できません|no disponible|nicht verfügbar|недоступен|não está disponível'; then
    log "窗口是启动失败对话框（title=$title），冒烟失败"
    tail -50 "$app_log" >&2
    exit 1
  fi
  # preload 抛错会让主进程走 fatal recovery，并把失败对话框当成"窗口"；必须单独判掉。
  if grep -q 'preload-app\.cjs' "$app_log" 2>/dev/null; then
    log "preload 抛错，冒烟失败"
    grep -n -A6 'preload-app\.cjs' "$app_log" | head -20 >&2
    exit 1
  fi
  xdotool getwindowgeometry "$window" || true
  sleep 5

  shot="$SHOT_DIR/shot.png"
  fired=""
  if command -v import >/dev/null 2>&1 && import -window root "$shot" 2>/dev/null && [[ -s "$shot" ]]; then
    fired=import
  fi
  if [[ -z "$fired" ]] && command -v scrot >/dev/null 2>&1; then
    rm -f "$shot"
    scrot "$shot" 2>/dev/null && [[ -s "$shot" ]] && fired=scrot
  fi
  if [[ -z "$fired" ]] && command -v gnome-screenshot >/dev/null 2>&1; then
    rm -f "$shot"
    gnome-screenshot -f "$shot" 2>/dev/null && [[ -s "$shot" ]] && fired=gnome-screenshot
  fi
  if [[ -n "$fired" ]]; then
    log "截图已存（$fired）：$shot（$(stat -c%s "$shot" 2>/dev/null || echo '?') 字节）"
  else
    rm -f "$shot"
    log "截图失败（import/scrot/gnome-screenshot 均无或全败，best-effort）"
  fi

  log "结论：窗口已建出，冒烟通过"
  exit 0
fi

# ---------- 阶段一：装包与工具 ----------
# 公钥先导入 rpmdb，再以 gpgcheck 强制安装：这一步同时验证签名和首个安装路径。
log "导入签名公钥并校验"
rpm --import /pkg-key.asc || { log "导入公钥失败"; exit 1; }
rpmkeys -K /pkg/*.rpm | grep -q 'digests signatures OK' || { log "rpm 签名校验失败"; exit 1; }

log "安装 rpm"
dnf5 install -y --setopt=install_weak_deps=False --setopt=localpkg_gpgcheck=1 /pkg/*.rpm \
  || { log "dnf5 安装失败"; exit 1; }
command -v "$APP" >/dev/null || { log "没装出 $APP"; exit 1; }

log "安装 X11 与 DBus 工具"
dnf5 install -y --setopt=install_weak_deps=False \
  xorg-x11-server-Xvfb ImageMagick xdotool dbus-daemon dbus-tools >/dev/null \
  || { log "装 X11 工具失败"; exit 1; }

# sharp 的纯 Node worker 读不了 app.asar；它的加载期依赖（detect-libc、semver）必须一起解包。
log "验证打包内 sharp 能解码图片"
probe=/tmp/probe.png
convert -size 16x16 'xc:#ff0000' "$probe" 2>/dev/null || magick -size 16x16 'xc:#ff0000' "$probe" 2>/dev/null
[ -s "$probe" ] || { log "没造出测试 PNG"; exit 1; }
pkg=/opt/deepseek-harness-desktop/resources
printf '{"id":1,"input":"%s","options":{"failOn":"error","limitInputPixels":false},"ops":[],"terminal":"metadata","args":[]}\n' \
  "$(base64 -w0 "$probe")" \
  | DSH_SHARP_MODULE_DIR="$pkg/app.asar.unpacked/dsh/node_modules" \
    "$pkg/runtime/primary-runtime/dependencies/node/bin/node" "$pkg/sharp-worker.cjs" \
  | grep -q '"ok":true' || { log "sharp worker 解码失败：检查 0021 的 asarUnpack 是否含 detect-libc 与 semver"; exit 1; }
log "sharp 解码 OK"

# 更新链（M5 + 渠道 C）：helper、polkit 策略、.repo 与公钥都由 rpm 拥有；helper 只接受唯一的
# 渠道参数 --channel=nightly|stable（无参=nightly，兼容旧应用），内部触发一次
# `dnf5 upgrade dsh-desktop`。这里真跑一次，验证参数契约与升级链都通。
log "验证更新链 helper 与 dnf 仓库"
[ -x /usr/libexec/dsh-update-helper ] || { log "缺少 /usr/libexec/dsh-update-helper"; exit 1; }
[ -f /usr/share/polkit-1/actions/org.deepseek.harness.desktop.update.policy ]   || { log "缺少 polkit 策略"; exit 1; }
[ -f /etc/yum.repos.d/dsh-desktop.repo ] || { log "缺少 /etc/yum.repos.d/dsh-desktop.repo"; exit 1; }
[ -f /etc/pki/rpm-gpg/RPM-GPG-KEY-dsh-desktop ] || { log "缺少随包公钥"; exit 1; }
# 公钥在 rpmdb 里是 NAME=gpg-pubkey、VERSION=指纹，按指纹尾 8 位判定是否已导入。
rpm -qa --qf '%{NAME} %{VERSION}\n' \
  | awk '$1 == "gpg-pubkey" && substr($2, length($2) - 7) == "c85f90ee"' | grep -q . \
  || { log "公钥没有导入 rpmdb"; exit 1; }
# M4：系统侧文件必须由 rpm 拥有、且安装后无校验差异。这些断言放在 helper 之前：
# helper 会 `dnf5 upgrade` 到仓库里的最新版，而仓库里的版本可能早于 M4（那时 helper 还是 %post 复制的），
# 升级后再断言归属就不再是在验证本次构建的包了。
rpm -q --whatprovides /usr/libexec/dsh-update-helper >/dev/null || { log "helper 不属于任何包"; exit 1; }
rpm -q --whatprovides /usr/share/polkit-1/actions/org.deepseek.harness.desktop.update.policy >/dev/null \
  || { log "polkit 策略不属于任何包"; exit 1; }
rpm -q --whatprovides /etc/yum.repos.d/dsh-desktop.repo >/dev/null || { log ".repo 不属于任何包"; exit 1; }
rpm -q --whatprovides /etc/pki/rpm-gpg/RPM-GPG-KEY-dsh-desktop >/dev/null || { log "公钥不属于任何包"; exit 1; }
rpm -q --whatprovides /var/log/dsh-desktop >/dev/null || { log "日志目录不属于任何包"; exit 1; }
# chrome-sandbox 的权限由 %post 按 user namespace 支持情况调整（4755 或 0755），
# 这是上游安装脚本的既定行为，允许它出现在差异里；其余任何差异都算失败。
sandbox_drift="$(rpm -V dsh-desktop | grep 'chrome-sandbox' || true)"
unexpected="$(rpm -V dsh-desktop | grep -v 'chrome-sandbox' || true)"
[[ -n "$sandbox_drift" ]] && log "chrome-sandbox 权限由 %post 调整（预期内）：$sandbox_drift"
[[ -z "$unexpected" ]] || { echo "$unexpected" >&2; log "rpm -V dsh-desktop 报告了预期之外的差异"; exit 1; }
# 先验参数契约：非法参数必须在动 dnf 之前以 64 退出。
rc=0
/usr/libexec/dsh-update-helper --channel=bogus >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 64 ] || { log "helper 对非法参数未返回 64（实际 $rc）"; exit 1; }
# 再真跑一次到 nightly。它可能把包换成仓库里的发布版，所以放在归属断言之后；
# 渠道仓库还没发布过内容时，dnf 按 .repo 的 skip_if_unavailable=1 跳过并 exit 0，
# 跳过提示由 helper 的 tee 落进 update.log（日志里能区分「跳过」与「Nothing to do」）。
/usr/libexec/dsh-update-helper --channel=nightly \
  || { log "helper 升级失败"; tail -20 /var/log/dsh-desktop/update.log >&2; exit 1; }
grep -q '升级成功' /var/log/dsh-desktop/update.log || { log "helper 没写出成功日志"; exit 1; }
rpm -q dsh-desktop >/dev/null || { log "helper 跑完后 dsh-desktop 不在 rpmdb"; exit 1; }
# helper 会把容器里的包换成仓库里的发布版，那一版的 /usr/bin 链接与本分支构建的包不一定一致。
# 后续要测的是本次构建的二进制，所以这里降级回 /pkg 里的包。
{ dnf5 downgrade -y --setopt=install_weak_deps=False --setopt=localpkg_gpgcheck=1 /pkg/*.rpm >/dev/null 2>&1 \
    || dnf5 install -y --setopt=install_weak_deps=False --setopt=localpkg_gpgcheck=1 /pkg/*.rpm >/dev/null 2>&1; } \
  || { log "helper 之后装回本次构建失败"; exit 1; }
log "装回本次构建：$(rpm -q --qf '%{VERSION}-%{RELEASE}' dsh-desktop)"
[ -x /opt/deepseek-harness-desktop/deepseek-harness ] \
  || { log "装回后缺少 /opt/deepseek-harness-desktop/deepseek-harness"; exit 1; }
log "更新链 helper 安装 OK"

# 授权链（#19 后的回归覆盖）：非 root 用户经 pkexec → polkit（implicit 全 yes 免认证）→
# helper → dnf5。容器没有 logind，进程无会话——正是 2026-11-05 127 事故的形状（当时靠策略
# allow_inactive=yes 放行）。helper 是真本体；dnf5 换成 stub：升级行为已在上面直跑验证过，
# 这里只验授权与执行链。替换按绝对路径落刀，不赌 pkexec 给 helper 的 PATH。
log "验证 pkexec 授权链（非 root、无 logind 会话）"
dnf5 install -y --setopt=install_weak_deps=False polkit >/dev/null \
  || { log "装 polkit 失败"; exit 1; }
mkdir -p /run/dbus
dbus-daemon --system --fork 2>/dev/null || log "system dbus 未自起（可能已在运行，继续）"
polkitd=/usr/lib/polkit-1/polkitd
[ -x "$polkitd" ] || { log "缺 polkitd"; exit 1; }
"$polkitd" >/dev/null 2>&1 &
ready=""
for _ in $(seq 1 10); do
  pkaction --verbose --action-id org.deepseek.harness.desktop.update 2>/dev/null | grep -q 'implicit any:.*yes' \
    && { ready=1; break; }
  sleep 1
done
if [ -z "$ready" ]; then
  log "polkit 未就绪（10 秒内 action 未免认证放行），现场："
  pgrep -a dbus-daemon || log "没有 dbus-daemon 进程"
  pgrep -a polkitd || log "没有 polkitd 进程"
  pkaction --verbose --action-id org.deepseek.harness.desktop.update 2>&1 | head -5 || true
  exit 1
fi
useradd -M -N -s /bin/bash smokeuser 2>/dev/null || true
rm -f /var/log/dsh-desktop/update.log
mv /usr/bin/dnf5 /usr/bin/dnf5.real
# stub 期间任何失败都要把真 dnf5 放回去；恢复成功后立刻拆掉 trap。
trap 'mv -f /usr/bin/dnf5.real /usr/bin/dnf5 2>/dev/null' EXIT
cat > /usr/bin/dnf5 <<'STUB'
#!/bin/bash
printf 'stub-dnf5 %s\n' "$*" >> /var/log/dsh-desktop/update.log
exit 0
STUB
chmod 755 /usr/bin/dnf5
# 与真机同形：应用侧只给 pkexec 设 LC_ALL=C，这里用 env -i 复刻该形态（无 PATH/HOME/
# 会话/DBus 变量），让「最小环境下授权链通」成为持续回归，而不是只有一次手工验证。
if su smokeuser -s /bin/sh -c 'env -i LC_ALL=C pkexec /usr/libexec/dsh-update-helper'; then
  grep -q '开始升级 dsh-desktop' /var/log/dsh-desktop/update.log \
    || { log "pkexec 执行了 helper 但 helper 没写开始日志"; exit 1; }
  grep -q '调用者 uid=' /var/log/dsh-desktop/update.log \
    || { log "helper 没记录调用者 uid"; exit 1; }
  grep -q 'stub-dnf5 upgrade' /var/log/dsh-desktop/update.log \
    || { log "helper 没调 dnf5 upgrade（stub 未命中）"; exit 1; }
  grep -q '升级成功' /var/log/dsh-desktop/update.log \
    || { log "helper 没走到成功出口"; exit 1; }
  log "授权链 OK：非 root 经 pkexec 免认证执行 helper，dnf5 由 stub 顶住"
else
  log "pkexec 授权链失败"
  tail -20 /var/log/dsh-desktop/update.log >&2
  exit 1
fi
mv -f /usr/bin/dnf5.real /usr/bin/dnf5
trap - EXIT
log "授权链验证完成，dnf5 已恢复"

export DSH_HOME=/tmp/dsh-home
mkdir -p "$DSH_HOME"
xvfb=(xvfb-run -a -s "-screen 0 1280x1024x24")

# 会话总线优先 dbus-run-session（在 dbus-daemon 包里）；没有就自起 dbus-daemon；再没有就无总线跑。
if command -v dbus-run-session >/dev/null 2>&1; then
  log "用 dbus-run-session 起会话总线"
  exec dbus-run-session -- "${xvfb[@]}" bash "$0" --launch
elif command -v dbus-daemon >/dev/null 2>&1; then
  export DBUS_SESSION_BUS_ADDRESS="$(dbus-daemon --session --fork --print-address)"
  log "自起 dbus-daemon：$DBUS_SESSION_BUS_ADDRESS"
  exec "${xvfb[@]}" bash "$0" --launch
else
  log "没有 dbus-run-session / dbus-daemon，无总线启动"
  exec "${xvfb[@]}" bash "$0" --launch
fi
