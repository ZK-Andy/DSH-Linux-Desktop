#!/usr/bin/env bash
# 在 fedora 容器里跑：装 rpm → 启动 → 确认建出窗口 → 截图。
# 由 scripts/smoke-install-rpm.sh 以 root 调用，/pkg 只读挂载产物，/shots 可写挂载截图输出。
set -uo pipefail

log() { printf '[rpm-smoke] %s\n' "$*"; }

dnf5 install -y --setopt=install_weak_deps=False /pkg/*.rpm || { log "dnf5 安装失败"; exit 1; }
command -v deepseek-harness || { log "没装出 /usr/bin/deepseek-harness"; exit 1; }

# Xvfb 提供虚拟显示；xdotool 用来确认窗口真的建出来；ImageMagick 提供 import。
dnf5 install -y --setopt=install_weak_deps=False \
  dbus-tools xorg-x11-server-Xvfb xorg-x11-utils ImageMagick xdotool >/dev/null || { log "装 X11 工具失败"; exit 1; }

export DSH_HOME=/tmp/dsh-home
mkdir -p /tmp/shots
cat > /tmp/inner.sh <<'INNER'
set -uo pipefail
/usr/bin/deepseek-harness --no-sandbox --disable-gpu > /tmp/app.log 2>&1 &
app=$!
window=""
for _ in $(seq 1 30); do
  sleep 2
  if ! kill -0 "$app" 2>/dev/null; then
    echo "app 在出窗口前退出"; cat /tmp/app.log; exit 1
  fi
  window=$(xdotool search --onlyvisible --name . 2>/dev/null | head -1 || true)
  [ -n "$window" ] && break
done
if [ -z "$window" ]; then
  echo "60 秒内没有可见窗口"; cat /tmp/app.log; exit 1
fi
xdotool getwindowgeometry "$window" || true
sleep 5
import -window root /tmp/shots/shot.png 2>/dev/null || scrot /tmp/shots/shot.png 2>/dev/null \
  || gnome-screenshot -f /tmp/shots/shot.png 2>/dev/null || echo "截图工具不可用（best-effort）"
kill "$app" 2>/dev/null || true
INNER

dbus-run-session -- xvfb-run -a -s "-screen 0 1280x1024x24" bash /tmp/inner.sh || exit 1
cp /tmp/shots/*.png /shots/ 2>/dev/null || true
log "完成"
