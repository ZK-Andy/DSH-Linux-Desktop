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
  "$APP" --no-sandbox --disable-gpu --disable-dev-shm-usage >"$app_log" 2>&1 &
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

  log "window=$window title=$(xdotool getwindowname "$window" 2>/dev/null || echo '?') class=$(xdotool getwindowclassname "$window" 2>/dev/null || echo '?')"
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
log "安装 rpm"
dnf5 install -y --setopt=install_weak_deps=False --setopt=localpkg_gpgcheck=0 /pkg/*.rpm \
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
