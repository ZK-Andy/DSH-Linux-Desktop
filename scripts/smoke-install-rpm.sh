#!/usr/bin/env bash
# rpm 冒烟入口（宿主侧）：只负责起 fedora:44 容器与挂载，容器内逻辑在 smoke-rpm-inner.sh。
#
#   SMOKE_SHOT_DIR=shots SMOKE_LOG_DIR=smoke-logs ./scripts/smoke-install-rpm.sh dist
#
# 与参考模板 scripts/smoke-linux-rpm.sh 同形：容器腿放脚本里，工作流只加一个 run；
# 截图与日志都落在宿主目录，由工作流按「冒烟跑过且失败则 error、否则 warn」上传。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$(realpath "${1:?usage: $0 <dir-with-rpm>}")"
[[ -n "$(find "$PKG_DIR" -maxdepth 1 -name '*.rpm' -print -quit)" ]] || {
  echo "目录里没有 rpm：$PKG_DIR" >&2
  exit 2
}

SHOT_DIR="${SMOKE_SHOT_DIR:-$ROOT/shots}"
LOG_DIR="${SMOKE_LOG_DIR:-$ROOT/smoke-logs}"
mkdir -p "$SHOT_DIR" "$LOG_DIR"

echo "== [rpm] fedora 容器安装冒烟：$(find "$PKG_DIR" -maxdepth 1 -name '*.rpm' -printf '%f\n' | head -1)"

docker_rc=0
docker run --rm \
  -v "$PKG_DIR:/pkg:ro" \
  -v "$ROOT/packaging/RPM-GPG-KEY-dsh-desktop:/pkg-key.asc:ro" \
  -v "$ROOT/scripts/smoke-rpm-inner.sh:/smoke-inner.sh:ro" \
  -v "$SHOT_DIR:/shots:rw" \
  -v "$LOG_DIR:/smokelogs:rw" \
  -e SMOKE_SHOT_DIR=/shots \
  -e SMOKE_LOG_DIR=/smokelogs \
  fedora:44 bash /smoke-inner.sh || docker_rc=$?

# 非零留痕：容器内外两层失败要能一眼分开（inner 的结论行在上文）。
if [[ "$docker_rc" -ne 0 ]]; then
  echo "== [rpm] 容器退出码 $docker_rc（inner 结论行见上文）" >&2
fi
echo "截图：$(ls "$SHOT_DIR" 2>/dev/null | tr '\n' ' ')"
echo "日志：$(ls "$LOG_DIR" 2>/dev/null | tr '\n' ' ')"
exit "$docker_rc"
